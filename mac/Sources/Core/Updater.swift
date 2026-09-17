import AppKit
import Foundation
import Observation

/// 软件更新。版本信息取自 GitHub Releases，安装包是通用二进制的 DMG
@MainActor
@Observable
final class Updater {
    struct Release: Equatable {
        let version: String
        let notes: String
        /// 字节
        let size: Int
        let url: URL
    }

    enum Phase: Equatable {
        case idle
        case checking
        case current
        case found(Release)
        case downloading(Release, Double)
        case ready(Release, URL)
        case installing
        case failed(String)
    }

    static let shared = Updater()
    static let page = URL(string: "https://github.com/UreMySunshine/hestia/releases")!
    private static let api = URL(
        string: "https://api.github.com/repos/UreMySunshine/hestia/releases/latest")!
    nonisolated private static let bundleID = "com.kira.hestia"
    /// 定时检查的间隔
    static let checkEvery: TimeInterval = 24 * 3600
    private static let checkedKey = "updateCheckedAt"
    /// 发现过、尚未装上的版本号。重启应用后据此立即重新检查，侧栏提示不会因为未满 24 小时而消失
    private static let foundKey = "updateFoundVersion"

    var phase: Phase = .idle
    var checkedAt: Date?

    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var enabled: () -> Bool = { false }

    private init() {
        checkedAt = UserDefaults.standard.object(forKey: Self.checkedKey) as? Date
    }

    /// 发现了新版本且尚未安装，侧栏据此提示
    var hasUpdate: Bool {
        switch phase {
        case .found, .downloading, .ready: true
        default: false
        }
    }

    nonisolated static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 只有正式版能覆盖安装；调试版的包标识与发布包不同，装上去会变成另一个应用
    nonisolated static var installable: Bool { Bundle.main.bundleIdentifier == bundleID }

    // MARK: 定时检查

    /// 启动后稍候检查一次，之后每小时看一眼距上次检查是否已满 24 小时
    func schedule(enabled: @escaping () -> Bool) {
        self.enabled = enabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, enabled() else { return }
            let found = UserDefaults.standard.string(forKey: Self.foundKey) ?? ""
            if Self.newer(found, than: Self.current) {
                self.check(silent: true)
            } else {
                self.checkIfDue()
            }
        }
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 开关打开、距上次检查已满 24 小时、且没有进行中的更新时，静默检查一次
    func checkIfDue() {
        guard enabled() else { return }
        switch phase {
        case .idle, .current, .failed: break
        default: return
        }
        if let last = checkedAt, Date().timeIntervalSince(last) < Self.checkEvery { return }
        check(silent: true)
    }

    // MARK: 检查

    /// `silent` 为真时是定时检查：失败时界面保持原状，一小时后再试
    func check(silent: Bool = false) {
        let before = phase
        phase = .checking
        Task {
            do {
                var req = URLRequest(url: Self.api)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { throw UpdateError("GitHub 返回 \(code)") }
                let info = try JSONDecoder().decode(Latest.self, from: data)
                let now = Date()
                checkedAt = now
                UserDefaults.standard.set(now, forKey: Self.checkedKey)

                let version = info.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard Self.newer(version, than: Self.current) else {
                    UserDefaults.standard.removeObject(forKey: Self.foundKey)
                    phase = .current
                    return
                }
                guard let dmg = info.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
                    throw UpdateError("\(version) 的发布里没有安装包")
                }
                let notes = (info.body ?? "")
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty } ?? ""
                UserDefaults.standard.set(version, forKey: Self.foundKey)
                phase = .found(
                    Release(
                        version: version, notes: notes, size: dmg.size,
                        url: dmg.browser_download_url))
            } catch {
                phase = silent ? before : .failed(Self.describe(error))
            }
        }
    }

    /// 逐段比较数字版本号，缺的段按 0 算
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: 下载

    func download(_ release: Release) {
        phase = .downloading(release, 0)
        let delegate = DownloadDelegate(
            progress: { [weak self] pct in
                DispatchQueue.main.async {
                    guard let self, case .downloading = self.phase else { return }
                    self.phase = .downloading(release, pct)
                }
            },
            done: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.session?.finishTasksAndInvalidate()
                    self.session = nil
                    switch result {
                    case .success(let file): self.phase = .ready(release, file)
                    case .failure(let error): self.phase = .failed(Self.describe(error))
                    }
                }
            })
        let s = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session = s
        s.downloadTask(with: release.url).resume()
    }

    // MARK: 安装

    /// 挂载安装包、核对包标识、替换当前应用，然后重新启动
    func install(_ dmg: URL) {
        phase = .installing
        let target = Bundle.main.bundleURL
        Task.detached {
            do {
                try Self.replace(target, from: dmg)
                await MainActor.run { Self.relaunch(target) }
            } catch {
                await MainActor.run { self.phase = .failed(Self.describe(error)) }
            }
        }
    }

    /// 无论成败，安装包、挂载点与暂存副本都在返回前删掉；失败后重试会重新下载
    nonisolated private static func replace(_ target: URL, from dmg: URL) throws {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: dmg) }
        let mount = fm.temporaryDirectory.appendingPathComponent("hestia-mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        // 在卸载之后执行。rmdir 只删空目录，卸载失败时不会动到仍挂着的卷
        defer { rmdir(mount.path) }
        try run(
            "/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }

        let items = try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
        guard let app = items.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError("安装包里没有应用")
        }
        guard Bundle(url: app)?.bundleIdentifier == bundleID else {
            throw UpdateError("安装包里的应用不是 Hestia")
        }

        let staged = fm.temporaryDirectory.appendingPathComponent("Hestia-\(UUID().uuidString).app")
        // 替换成功时暂存副本已被移走，这里只清理复制或替换失败留下的
        defer { try? fm.removeItem(at: staged) }
        try run("/usr/bin/ditto", [app.path, staged.path])
        _ = try fm.replaceItemAt(target, withItemAt: staged)
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) 退出码 \(p.terminationStatus)")
        }
    }

    /// 退出后由一个脱离的 shell 重新打开新版本
    private static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    nonisolated private static func describe(_ error: Error) -> String {
        (error as? UpdateError)?.message ?? error.localizedDescription
    }
}

private struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// GitHub Releases 接口里用得到的字段
private struct Latest: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int
        let browser_download_url: URL
    }

    let tag_name: String
    let body: String?
    let assets: [Asset]
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: (Double) -> Void
    private let done: (Result<URL, Error>) -> Void
    private var reported = -1
    private var finished = false

    init(progress: @escaping (Double) -> Void, done: @escaping (Result<URL, Error>) -> Void) {
        self.progress = progress
        self.done = done
    }

    /// 每涨一个百分点才上报，免得界面每收一块数据就刷新一次
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let pct = Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
        guard pct != reported else { return }
        reported = pct
        progress(Double(pct) / 100)
    }

    /// 临时文件在这个回调返回后就会被删掉，必须同步移走
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        finished = true
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            done(.failure(UpdateError("下载返回 \(code)")))
            return
        }
        let fm = FileManager.default
        let dest = fm.temporaryDirectory.appendingPathComponent("Hestia-update.dmg")
        try? fm.removeItem(at: dest)
        do {
            try fm.moveItem(at: location, to: dest)
            done(.success(dest))
        } catch {
            done(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, !finished else { return }
        done(.failure(error))
    }
}
