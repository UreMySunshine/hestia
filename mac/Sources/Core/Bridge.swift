import Foundation
import HestiaCore

/// Rust 核心的调用入口。
///
/// 核心通过 C 函数指针回调，而 `@convention(c)` 闭包不能捕获上下文，
/// 因此事件转发挂在这里的静态属性上。回调来自 Rust 的后台线程，统一切回主线程再交给界面。
enum Bridge {
    nonisolated(unsafe) static var onLogs: (([LogLine]) -> Void)?
    nonisolated(unsafe) static var onServicesChanged: (() -> Void)?

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()
    static let decoder = JSONDecoder()

    /// 初始化核心。配置目录按 bundle 标识取，正式版沿用 Tauri 版本的 com.kira.hestia，
    /// 原有服务配置直接可用；调试版标识不同，自然落在另一份配置里。
    /// 两个实例共用一个目录会互相回收对方的进程，`HESTIA_CONFIG_DIR` 可另指一份
    static func start() {
        // GUI 由 launchd 拉起，PATH 里没有 nvm、pnpm 这些装在用户目录下的工具，
        // 先从登录 shell 取回真实 PATH，之后 spawn 的服务子进程才能继承到
        hestia_bootstrap()

        let dir = ProcessInfo.processInfo.environment["HESTIA_CONFIG_DIR"].map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        } ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "com.kira.hestia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        hestia_init(dir.path, handleEvent)
    }

    /// 调用核心并解码返回值
    static func call<T: Decodable>(_ method: String, _ args: String = "null") -> T? {
        guard let raw = hestia_call(method, args) else { return nil }
        defer { hestia_free(raw) }
        let data = Data(bytes: raw, count: strlen(raw))
        return try? decoder.decode(T.self, from: data)
    }

    /// 调用核心并丢弃返回值
    static func send(_ method: String, _ args: String = "null") {
        guard let raw = hestia_call(method, args) else { return }
        hestia_free(raw)
    }

    static func send(_ method: String, id: String) {
        send(method, json(["id": id]))
    }

    static func json(_ value: some Encodable) -> String {
        guard let d = try? encoder.encode(value) else { return "null" }
        return String(decoding: d, as: UTF8.self)
    }
}

private func handleEvent(_ name: UnsafePointer<CChar>?, _ payload: UnsafePointer<CChar>?) {
    guard let name else { return }
    let event = String(cString: name)
    let body = payload.map { String(cString: $0) } ?? "null"

    switch event {
    case "logs":
        guard let lines = try? Bridge.decoder.decode([LogLine].self, from: Data(body.utf8)) else { return }
        DispatchQueue.main.async { Bridge.onLogs?(lines) }
    case "services-changed":
        DispatchQueue.main.async { Bridge.onServicesChanged?() }
    default:
        break
    }
}
