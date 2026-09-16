import Foundation
import Observation

/// 采样节拍
private let tickInterval: TimeInterval = 1.4
/// 每条曲线保留的采样点数
let histLength = 40
/// 日志缓冲行数，与核心的 LOG_CAP 一致
let logCap = 4000
/// 启停记录与报错输出各保留的条数
let entryCap = 50

enum Screen: Hashable {
    case overview, detail, monitor, settings
}

enum LogMode: String, CaseIterable {
    case this, all, err

    var label: String {
        switch self {
        case .this: "本服务"
        case .all: "全部"
        case .err: "仅错误"
        }
    }
}

enum MonitorSort: String, CaseIterable {
    case none = "默认"
    case cpu = "CPU"
    case mem = "内存"
    case name = "名称"

    var help: String { self == .none ? "按配置顺序" : "按\(rawValue)从高到低" }
}

enum StateFilter: String, CaseIterable {
    case all = "全部"
    case running = "运行中"
    case stopped = "已停止"
    case error = "异常"

    func accepts(_ state: RunState) -> Bool {
        switch self {
        case .all: true
        case .running: state == .running
        case .stopped: state == .stopped
        case .error: state == .error
        }
    }
}

/// 侧边栏与总览只关心状态、端口和累计次数，它们的变化远少于每拍都在动的 CPU、内存。
/// 单独存一份粗粒度数据，避免一次采样就让读到 `status` 的视图全部失效——
/// 侧边栏是 NSTableView，那样每拍都会触发整个窗口的视图树重排
struct ServiceBrief: Equatable {
    var state: RunState
    var port: UInt16?
    var errors = 0
    var restarts = 0

    static let idle = ServiceBrief(state: .stopped, port: nil)
}

/// 发出启停指令后维持的过渡
struct Transition {
    let phase: Phase
    let since: Date
}

@Observable
final class Store {
    // 配置
    var services: [ServiceConfig] = []
    var prefs: Prefs = .fallback

    // 运行态
    var status: [String: ServiceStatus] = [:]
    var brief: [String: ServiceBrief] = [:]
    /// 键为服务 id。只在发出指令和过渡结束时变化
    var pending: [String: Transition] = [:]
    var own: SelfStatus = .zero
    var cores = 1
    var ready = false

    // 采样历史
    var cpuHist: [String: [Double]] = [:]
    var memHist: [String: [Double]] = [:]
    var selfHist = [Double](repeating: 0, count: histLength)
    var totalCpuHist = [Double](repeating: 0, count: histLength)
    var totalMemHist = [Double](repeating: 0, count: histLength)

    var logs: [LogLine] = []
    /// 核心写入的启停记录，不受日志缓冲上限裁剪
    var activity: [LogEntry] = []
    /// 服务自身输出里的报错与警告
    var problems: [LogEntry] = []

    // 本次运行的统计，从应用启动算起
    let launchedAt = Date()
    /// 按分钟前进的时刻。只需分钟精度的视图读它，不随每拍采样重绘
    var minute = Date()
    var starts = 0
    /// 各服务运行中的时段
    var spans: [String: [RunSpan]] = [:]
    /// 各服务停在异常状态的时段
    var faultSpans: [String: [RunSpan]] = [:]
    /// 各服务异常退出的时刻
    var crashes: [String: [Date]] = [:]

    // 导航
    var screen: Screen = .overview
    var selection: String = ""
    var appearance: Appearance = .system
    var drawerOpen = false

    // 各页面里用户选过的筛选与分页，页面切走再回来要保持
    var monitorFilter: StateFilter = .all
    var monitorQuery = ""
    var monitorSort: MonitorSort = .none
    var logMode: LogMode = .this
    var followLogs = true

    @ObservationIgnored private var timer: Timer?

    // MARK: 生命周期

    func boot() {
        // 必须先初始化核心：SwiftUI 的 onAppear 会早于 applicationDidFinishLaunching，
        // 放在应用代理里初始化，这里读到的会是空配置
        Bridge.start()

        // 核心在进程拉起、退出、失败时都会发这个事件，借它及时结束过渡
        Bridge.onServicesChanged = { [weak self] in
            self?.reloadConfig()
            self?.refresh(record: false)
            self?.settle()
        }
        Bridge.onLogs = { [weak self] lines in self?.append(lines) }

        reloadConfig()
        logs = Bridge.call("get_logs") ?? []
        remember(logs)
        if selection.isEmpty { selection = services.first?.id ?? "" }
        tick()
        ready = true

        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        LoginItem.sync(prefs.autostart)
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        Bridge.send("kill_all_now")
    }

    // MARK: 数据

    private func reloadConfig() {
        let cfg: AppConfig = Bridge.call("get_config") ?? .empty
        services = cfg.services
        prefs = cfg.prefs
        let ids = Set(cfg.services.map(\.id))
        status = status.filter { ids.contains($0.key) }
        brief = brief.filter { ids.contains($0.key) }
        cpuHist = cpuHist.filter { ids.contains($0.key) }
        memHist = memHist.filter { ids.contains($0.key) }
        if !ids.contains(selection) { selection = services.first?.id ?? "" }
    }

    private func tick() {
        refresh(record: true)
        settle()
    }

    /// 取一次快照。只有按节拍的采样才写进曲线，事件触发的补采不写，免得曲线疏密不均
    private func refresh(record: Bool) {
        guard let snap: Snapshot = Bridge.call("snapshot") else { return }
        if cores != snap.cores { cores = snap.cores }
        var next: [String: ServiceBrief] = [:]
        for s in snap.services {
            status[s.id] = s
            next[s.id] = ServiceBrief(
                state: s.state, port: s.ports.first, errors: s.errors, restarts: s.restarts)
            if record {
                push(&cpuHist[s.id, default: zeros()], s.cpu)
                push(&memHist[s.id, default: zeros()], s.mem)
            }
        }
        if next != brief {
            track(from: brief, to: next)
            brief = next
        }
        guard record else { return }
        let now = Date()
        if Int(now.timeIntervalSince1970 / 60) != Int(minute.timeIntervalSince1970 / 60) { minute = now }
        own = snap.own
        push(&selfHist, snap.own.cpu)
        push(&totalCpuHist, snap.services.reduce(0) { $0 + $1.cpu })
        push(&totalMemHist, snap.services.reduce(0) { $0 + $1.mem })
    }

    /// 结束已经到位的过渡。设计稿里启动过渡 0.76 秒、停止 0.4 秒，
    /// 进程实际更慢时等到状态真正变化；30 秒仍未到位就放弃
    private func settle() {
        let now = Date()
        for (id, t) in pending {
            let state = brief(id).state
            let reached = t.phase == .starting ? state != .stopped : state != .running
            let age = now.timeIntervalSince(t.since)
            let minimum = t.phase == .starting ? 0.76 : 0.4
            if age > 30 || (reached && age >= minimum) {
                pending[id] = nil
            } else if reached {
                DispatchQueue.main.asyncAfter(deadline: .now() + minimum - age) { [weak self] in
                    self?.settle()
                }
            }
        }
    }

    private func begin(_ id: String, _ phase: Phase) {
        pending[id] = Transition(phase: phase, since: Date())
    }

    private func append(_ lines: [LogLine]) {
        logs.append(contentsOf: lines)
        if logs.count > logCap { logs.removeFirst(logs.count - logCap) }
        remember(lines)
    }

    /// 核心的启停记录以「[服务名] 」开头，其余报错与警告来自服务自身输出。
    /// 没有挑出内容时不写回，普通输出不触发首页更新
    private func remember(_ lines: [LogLine]) {
        let names = Dictionary(services.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var events: [LogEntry] = []
        var faults: [LogEntry] = []
        for l in lines {
            let name = names[l.sid] ?? ""
            let tag = "[\(name)] "
            if !name.isEmpty, l.txt.hasPrefix(tag) {
                events.append(
                    LogEntry(
                        id: l.id, sid: l.sid, name: name, text: String(l.txt.dropFirst(tag.count)),
                        lvl: l.lvl, ts: l.ts))
            } else if l.lvl == "ERROR" || l.lvl == "WARN" {
                faults.append(
                    LogEntry(id: l.id, sid: l.sid, name: name, text: l.txt, lvl: l.lvl, ts: l.ts))
            }
        }
        if !events.isEmpty { activity = Array((activity + events).suffix(entryCap)) }
        if !faults.isEmpty { problems = Array((problems + faults).suffix(entryCap)) }
    }

    /// 按状态变化记下运行时段、异常时段与异常退出的时刻
    private func track(from old: [String: ServiceBrief], to new: [String: ServiceBrief]) {
        let now = Date()
        for (id, b) in new {
            let was = old[id]?.state ?? .stopped
            guard b.state != was else { continue }
            if was == .running { close(&spans, id, at: now) }
            if was == .error { close(&faultSpans, id, at: now) }
            if b.state == .running {
                starts += 1
                // 进程可能早于这次采样启动，按它自报的运行秒数回推
                let up = status[id]?.up ?? 0
                spans[id, default: []].append(RunSpan(start: now.addingTimeInterval(-up)))
            } else if b.state == .error {
                crashes[id, default: []].append(now)
                faultSpans[id, default: []].append(RunSpan(start: now))
            }
        }
    }

    private func close(_ table: inout [String: [RunSpan]], _ id: String, at now: Date) {
        guard var list = table[id], list.last?.end == nil else { return }
        list[list.count - 1].end = now
        table[id] = list
    }

    private func zeros() -> [Double] { [Double](repeating: 0, count: histLength) }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > histLength { arr.removeFirst(arr.count - histLength) }
    }

    // MARK: 查询

    func status(_ id: String) -> ServiceStatus { status[id] ?? .idle(id) }
    func brief(_ id: String) -> ServiceBrief { brief[id] ?? .idle }
    func phase(_ id: String) -> Phase { pending[id]?.phase ?? Phase(brief(id).state) }

    /// 配置里写死的端口只在没探到实际端口时兜底
    func port(_ svc: ServiceConfig) -> UInt16? {
        brief(svc.id).port ?? (svc.port == 0 ? nil : svc.port)
    }
    func cpuSeries(_ id: String) -> [Double] { cpuHist[id] ?? zeros() }
    func memSeries(_ id: String) -> [Double] { memHist[id] ?? zeros() }

    func service(_ id: String) -> ServiceConfig? { services.first { $0.id == id } }

    var selected: ServiceConfig? { service(selection) ?? services.first }

    var runningCount: Int { services.filter { brief($0.id).state == .running }.count }
    var stoppedCount: Int { services.filter { brief($0.id).state == .stopped }.count }
    var errorCount: Int { services.filter { brief($0.id).state == .error }.count }
    var totalCpu: Double { services.reduce(0) { $0 + status($1.id).cpu } }
    /// 单位 MB
    var totalMem: Double { services.reduce(0) { $0 + status($1.id).mem } }

    func count(_ f: StateFilter) -> Int {
        f == .all ? services.count : services.filter { f.accepts(brief($0.id).state) }.count
    }

    // MARK: 动作

    func start(_ id: String) {
        begin(id, .starting)
        Bridge.send("start_service", id: id)
    }

    func stop(_ id: String) {
        begin(id, .stopping)
        Bridge.send("stop_service", id: id)
    }

    func restart(_ id: String) {
        begin(id, .starting)
        Bridge.send("restart_service", id: id)
    }

    func startAll() {
        for s in services where !phase(s.id).up { begin(s.id, .starting) }
        Bridge.send("start_all")
    }

    func stopAll() {
        for s in services where phase(s.id).up { begin(s.id, .stopping) }
        Bridge.send("stop_all")
    }

    func toggle(_ id: String) {
        phase(id).up ? stop(id) : start(id)
    }

    func save(_ svc: ServiceConfig) {
        Bridge.send("save_service", Bridge.json(svc))
        reloadConfig()
    }

    func delete(_ id: String) {
        Bridge.send("delete_service", id: id)
        reloadConfig()
    }

    func reorder(_ ids: [String]) {
        Bridge.send("reorder_services", Bridge.json(["ids": ids]))
        reloadConfig()
    }

    func update(prefs next: Prefs) {
        if next.autostart != prefs.autostart { LoginItem.sync(next.autostart) }
        prefs = next
        Bridge.send("set_prefs", Bridge.json(next))
    }

    func clearLogs() {
        Bridge.send("clear_logs")
        logs = []
        problems = []
    }

    func open(_ id: String) {
        selection = id
        screen = .detail
    }
}
