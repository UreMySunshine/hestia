import Foundation

struct EnvVar: Codable, Hashable {
    var k: String
    var v: String
}

struct ServiceConfig: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var proj: String
    /// 图标键，对应 ServiceIcon 表
    var ic: String
    var cmd: String
    var stop: String
    var cwd: String
    /// 0 表示不监听端口
    var port: UInt16
    var autoRestart: Bool
    var env: [EnvVar]

    static func blank() -> ServiceConfig {
        ServiceConfig(
            id: UUID().uuidString, name: "", proj: "", ic: "web",
            cmd: "", stop: "", cwd: "", port: 0, autoRestart: true, env: [])
    }
}

struct Prefs: Codable, Hashable {
    var autostart: Bool
    var autorestart: Bool
    var quiet: Bool

    static let fallback = Prefs(autostart: false, autorestart: true, quiet: true)
}

struct AppConfig: Codable {
    var services: [ServiceConfig]
    var prefs: Prefs

    static let empty = AppConfig(services: [], prefs: .fallback)
}

enum RunState: String, Codable {
    case running, stopped, error

    var label: String {
        switch self {
        case .running: "运行中"
        case .stopped: "已停止"
        case .error: "异常"
        }
    }
}

/// 界面展示的运行阶段。核心只报告运行、停止、异常；启动中、停止中是发出指令后界面维持的过渡
enum Phase: Equatable {
    case running, stopped, error, starting, stopping

    init(_ state: RunState) {
        switch state {
        case .running: self = .running
        case .stopped: self = .stopped
        case .error: self = .error
        }
    }

    var busy: Bool { self == .starting || self == .stopping }

    /// 正在运行或正在启动，此时按钮的动作是停止
    var up: Bool { self == .running || self == .starting }

    var label: String {
        switch self {
        case .running: "运行中"
        case .stopped: "已停止"
        case .error: "异常"
        case .starting: "启动中"
        case .stopping: "停止中"
        }
    }
}

struct ServiceStatus: Codable {
    var id: String
    var state: RunState
    var pid: Int
    /// 进程树 CPU 占用百分比，单核为 100
    var cpu: Double
    /// 进程树常驻内存，单位 MB
    var mem: Double
    /// 运行秒数
    var up: Double
    var restarts: Int
    var errors: Int
    /// 配置的端口是否确实由本服务的进程树在监听
    var portOpen: Bool
    /// 实际探测到的监听端口
    var ports: [UInt16]
    var lastError: String

    static func idle(_ id: String) -> ServiceStatus {
        ServiceStatus(
            id: id, state: .stopped, pid: 0, cpu: 0, mem: 0, up: 0, restarts: 0,
            errors: 0, portOpen: false, ports: [], lastError: "")
    }
}

struct SelfStatus: Codable {
    var pid: Int
    var cpu: Double
    var mem: Double
    var up: Double

    static let zero = SelfStatus(pid: 0, cpu: 0, mem: 0, up: 0)
}

struct Snapshot: Codable {
    var services: [ServiceStatus]
    var own: SelfStatus
    /// 逻辑核心数。cpu 是「占单核的百分比」，换算成占整机多少要除以它
    var cores: Int

    static let empty = Snapshot(services: [], own: .zero, cores: 1)
}

/// 带上服务名的一条日志
struct LogEntry: Identifiable {
    let id: String
    let sid: String
    let name: String
    /// 启停记录已去掉「[服务名] 」前缀
    let text: String
    let lvl: String
    /// Unix 毫秒
    let ts: UInt64
}

/// 一段保持同一状态的时间，状态未结束时 end 为空
struct RunSpan {
    let start: Date
    var end: Date?
}

struct LogLine: Codable, Identifiable, Equatable {
    var id: String
    /// Unix 毫秒
    var ts: UInt64
    var lvl: String
    var txt: String
    /// 来源服务 id
    var sid: String
}
