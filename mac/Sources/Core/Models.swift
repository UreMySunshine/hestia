import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct EnvVar: Codable, Hashable {
    var k: String
    var v: String
}

/// 默认方案的 id，指服务自身的命令与环境变量
let defaultProfile = "default"

/// 服务的另一套启动方式。命令留空时沿用服务自身的，环境变量按名覆盖或追加
struct Profile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var cmd: String
    var stop: String
    var env: [EnvVar]
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
    /// 当前方案
    var profile: String
    var profiles: [Profile]

    static func blank() -> ServiceConfig {
        ServiceConfig(
            id: UUID().uuidString, name: "", proj: "", ic: "web",
            cmd: "", stop: "", cwd: "", port: 0, autoRestart: true, env: [],
            profile: defaultProfile, profiles: [])
    }

    /// 找不到的方案按默认方案处理，与核心一致
    func profileID(_ id: String) -> String {
        profiles.contains { $0.id == id } ? id : defaultProfile
    }

    func profileName(_ id: String) -> String {
        profiles.first { $0.id == id }?.name ?? "默认"
    }

    /// 一行说明某个方案与默认方案的差别，供方案卡片与菜单使用
    func profileSummary(_ id: String) -> String {
        guard id != defaultProfile else { return "服务自身的配置" }
        let l = launch(id)
        var parts: [String] = []
        if l.cmdOwn { parts.append("替换启动命令") }
        if l.overrides > 0 { parts.append("另设 \(l.overrides) 个变量") }
        return parts.isEmpty ? "与默认方案相同" : parts.joined(separator: " · ")
    }

    /// 某个方案实际使用的配置，每一项带上来源
    func launch(_ id: String) -> Launch {
        guard let p = profiles.first(where: { $0.id == id }) else {
            return Launch(
                cmd: cmd, cmdOwn: false, stop: stop, stopOwn: false,
                env: env.map { Launch.Var(k: $0.k, v: $0.v, own: false, base: nil) })
        }
        var vars = env.map { Launch.Var(k: $0.k, v: $0.v, own: false, base: nil) }
        for e in p.env {
            let k = e.k.trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty else { continue }
            if let i = vars.firstIndex(where: { $0.k.trimmingCharacters(in: .whitespaces) == k }) {
                vars[i] = Launch.Var(k: k, v: e.v, own: true, base: vars[i].v)
            } else {
                vars.append(Launch.Var(k: k, v: e.v, own: true, base: nil))
            }
        }
        let blank = { (s: String) in s.trimmingCharacters(in: .whitespaces).isEmpty }
        return Launch(
            cmd: blank(p.cmd) ? cmd : p.cmd, cmdOwn: !blank(p.cmd),
            stop: blank(p.stop) ? stop : p.stop, stopOwn: !blank(p.stop),
            env: vars)
    }
}

/// 合并后的启动配置。`own` 表示这一项由方案提供
struct Launch {
    struct Var: Hashable {
        var k: String
        var v: String
        var own: Bool
        /// 被方案覆盖掉的默认值
        var base: String?
    }

    var cmd: String
    var cmdOwn: Bool
    var stop: String
    var stopOwn: Bool
    var env: [Var]

    var overrides: Int { env.filter(\.own).count }
}

enum StepKind: String, Codable, Hashable {
    case service, command
}

enum ReadyKind: String, Codable, Hashable, CaseIterable {
    case port, delay

    var label: String {
        switch self {
        case .port: "端口开始监听"
        case .delay: "等待秒数"
        }
    }
}

/// 工作流里的一步。服务步骤与命令步骤共用一个结构，与核心一致
struct Step: Codable, Identifiable, Hashable {
    var id: String
    var kind: StepKind
    var service: String
    /// 空串表示跟随服务的当前方案
    var profile: String
    var ready: ReadyKind
    var name: String
    var cmd: String
    var cwd: String
    /// 等待端口与命令步骤是超时秒数，按时长就绪是等待秒数
    var seconds: UInt64

    static func service(_ id: String) -> Step {
        Step(
            id: UUID().uuidString, kind: .service, service: id, profile: "", ready: .port,
            name: "", cmd: "", cwd: "", seconds: 120)
    }

    static func command(cwd: String) -> Step {
        Step(
            id: UUID().uuidString, kind: .command, service: "", profile: "", ready: .port,
            name: "", cmd: "", cwd: cwd, seconds: 300)
    }
}

struct Stage: Codable, Identifiable, Hashable {
    var id: String
    var steps: [Step]

    static func blank() -> Stage { Stage(id: UUID().uuidString, steps: []) }
}

/// 工作流编辑界面里拖拽传递的条目 id。用自己的类型，免得被输入框当成文本收下
struct StageDrag: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .hestiaStageItem)
    }
}

extension UTType {
    /// 同时在 mac/build.sh 生成的 Info.plist 里声明
    static let hestiaStageItem = UTType(exportedAs: "com.kira.hestia.stage-item")
}

/// 工作流编辑界面里拖放引起的列表改动。与界面无关，便于单独验证
enum StageEdit {
    enum Item: Equatable {
        case step(stage: String, step: String)
        case stage(String)
    }

    /// 拖拽只传 id，按 id 找出它是阶段还是其中一个步骤
    static func locate(_ id: String, in stages: [Stage]) -> Item? {
        if stages.contains(where: { $0.id == id }) { return .stage(id) }
        if let stage = stages.first(where: { $0.steps.contains { $0.id == id } }) {
            return .step(stage: stage.id, step: id)
        }
        return nil
    }

    /// 把步骤放到 `target` 步骤之前或之后，可跨阶段。返回是否有改动
    static func move(
        step id: String, before target: String, after below: Bool, in stages: inout [Stage]
    ) -> Bool {
        guard id != target, case .step(let from, _) = locate(id, in: stages),
            case .step(let into, _) = locate(target, in: stages),
            let fi = stages.firstIndex(where: { $0.id == from }),
            let si = stages[fi].steps.firstIndex(where: { $0.id == id })
        else { return false }
        let step = stages[fi].steps.remove(at: si)
        guard let ti = stages.firstIndex(where: { $0.id == into }),
            let k = stages[ti].steps.firstIndex(where: { $0.id == target })
        else {
            stages[fi].steps.insert(step, at: si)
            return false
        }
        stages[ti].steps.insert(step, at: below ? k + 1 : k)
        return true
    }

    /// 把步骤挪到某个阶段的末尾。已经在末尾时不动
    static func move(step id: String, toEndOf stage: String, in stages: inout [Stage]) -> Bool {
        guard case .step(let from, _) = locate(id, in: stages),
            let fi = stages.firstIndex(where: { $0.id == from }),
            let ti = stages.firstIndex(where: { $0.id == stage }),
            from != stage || stages[ti].steps.last?.id != id,
            let si = stages[fi].steps.firstIndex(where: { $0.id == id })
        else { return false }
        let step = stages[fi].steps.remove(at: si)
        stages[ti].steps.append(step)
        return true
    }

    /// 把阶段挪到 `target` 阶段之前或之后
    static func move(
        stage id: String, before target: String, after below: Bool, in stages: inout [Stage]
    ) -> Bool {
        guard id != target, let from = stages.firstIndex(where: { $0.id == id }),
            stages.contains(where: { $0.id == target })
        else { return false }
        let stage = stages.remove(at: from)
        guard let to = stages.firstIndex(where: { $0.id == target }) else {
            stages.insert(stage, at: from)
            return false
        }
        stages.insert(stage, at: below ? to + 1 : to)
        return true
    }
}

struct Workflow: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// 图标底色，取值见 `FlowColor`
    var color: String
    var stages: [Stage]

    /// 新工作流取一个其它工作流还没用过的颜色
    static func blank(among existing: [Workflow]) -> Workflow {
        Workflow(
            id: UUID().uuidString, name: "", color: FlowColor.next(used: existing.map(\.color)),
            stages: [.blank()])
    }

    var steps: [Step] { stages.flatMap(\.steps) }
}

struct Prefs: Codable, Hashable {
    var autostart: Bool
    var autorestart: Bool
    var quiet: Bool
    /// 日志缓冲保留的行数，范围与核心一致
    var logLines: Int
    /// 每天自动检查一次软件更新
    var autoUpdate: Bool

    static let fallback = Prefs(
        autostart: false, autorestart: true, quiet: true, logLines: 4000, autoUpdate: true)
    static let logLinesRange = 1000...20000
    static let logLinesStep = 1000
}

/// 核心对导入导出等操作的答复
struct BridgeReply: Decodable {
    var ok: Bool?
    var error: String?
    var config: AppConfig?
}

struct AppConfig: Codable {
    var services: [ServiceConfig]
    var workflows: [Workflow]
    var prefs: Prefs

    static let empty = AppConfig(services: [], workflows: [], prefs: .fallback)
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

/// 界面展示的运行阶段。核心只报告运行、停止、异常；启动中、停止中、切换中是发出指令后界面维持的过渡
enum Phase: Equatable {
    case running, stopped, error, starting, stopping, switching

    init(_ state: RunState) {
        switch state {
        case .running: self = .running
        case .stopped: self = .stopped
        case .error: self = .error
        }
    }

    var busy: Bool { self == .starting || self == .stopping || self == .switching }

    /// 正在运行或正在启动，此时按钮的动作是停止
    var up: Bool { self == .running || self == .starting || self == .switching }

    var label: String {
        switch self {
        case .running: "运行中"
        case .stopped: "已停止"
        case .error: "异常"
        case .starting: "启动中"
        case .stopping: "停止中"
        case .switching: "切换中"
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
    /// 运行中的进程所用的方案，未运行时为空
    var profile: String

    static func idle(_ id: String) -> ServiceStatus {
        ServiceStatus(
            id: id, state: .stopped, pid: 0, cpu: 0, mem: 0, up: 0, restarts: 0,
            errors: 0, portOpen: false, ports: [], lastError: "", profile: "")
    }
}

enum FlowState: String, Codable {
    case idle, running, done, failed, stopped
}

enum StepState: String, Codable {
    case pending, running, done, failed, skipped, stopped
}

/// 工作流对外显示的状态，侧栏、菜单栏、命令面板与运行页共用。
/// 启动过且未停止的工作流按所含服务显示已启动或部分运行；
/// 没有启动的工作流，服务恰好在运行时显示已就绪或部分就绪。
/// 手动停止后显示已停止，直到重新运行或所含服务又全部按方案运行
enum FlowShown: Equatable {
    case running, failed
    /// 启动后服务全部在运行、部分在运行
    case started, partial
    /// 没有启动，服务恰好全部在运行、部分在运行
    case ready, partlyReady
    case stopped, idle

    init(state: FlowState, members: Int, matched: Int) {
        let all = members > 0 && matched == members
        switch state {
        case .running: self = .running
        case .failed: self = .failed
        case .done where matched > 0: self = all ? .started : .partial
        default:
            if all {
                self = .ready
            } else if state == .stopped || state == .done && members > 0 {
                // 启动过但服务已全部被单独停掉，也按已停止显示
                self = .stopped
            } else {
                self = matched > 0 ? .partlyReady : .idle
            }
        }
    }

    /// 工作流已启动且未停止，启停按钮是停止
    var active: Bool { self == .running || self == .started || self == .partial }

    var label: String {
        switch self {
        case .running: "进行中"
        case .failed: "失败"
        case .started: "已启动"
        case .partial: "部分运行"
        case .ready: "已就绪"
        case .partlyReady: "部分就绪"
        case .stopped: "已停止"
        case .idle: "未运行"
        }
    }
}

struct StepStatus: Codable, Equatable {
    var id: String
    var state: StepState
    var detail: String
    var elapsed: Double
}

struct FlowEvent: Codable, Equatable {
    /// Unix 毫秒
    var ts: UInt64
    /// start、done、error 或 info
    var kind: String
    var text: String
}

struct WorkflowStatus: Codable, Equatable {
    var id: String
    var state: FlowState
    var stage: Int
    /// 本次运行开始的 Unix 毫秒，未运行过为 0
    var started: UInt64
    var elapsed: Double
    var steps: [StepStatus]
    var message: String
    var events: [FlowEvent]
    /// 工作流涉及的服务数
    var members: Int
    /// 其中正按工作流指定的方案运行的服务数
    var matched: Int

    static func idle(_ id: String) -> WorkflowStatus {
        WorkflowStatus(
            id: id, state: .idle, stage: 0, started: 0, elapsed: 0, steps: [], message: "",
            events: [], members: 0, matched: 0)
    }

    var brief: FlowBrief {
        FlowBrief(state: state, stage: stage, members: members, matched: matched)
    }

    func step(_ id: String) -> StepStatus {
        steps.first { $0.id == id } ?? StepStatus(id: id, state: .pending, detail: "", elapsed: 0)
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
    var workflows: [WorkflowStatus]
    var own: SelfStatus
    /// 逻辑核心数。cpu 是「占单核的百分比」，换算成占整机多少要除以它
    var cores: Int

    static let empty = Snapshot(services: [], workflows: [], own: .zero, cores: 1)
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
