import AppKit

@main
struct BehaviorTests {
    @MainActor
    static func main() {
        for input in ["abc", "-1", "0", "65536", "51x73", "999999999999999999999"] {
            precondition(FormValidation.port(input) == nil, input)
        }
        precondition(FormValidation.port("") == 0)
        precondition(FormValidation.port(" 5173 ") == 5173)
        precondition(FormValidation.port("65535") == 65535)

        var service = ServiceConfig.blank()
        service.id = "web"
        service.cmd = "echo configured"
        service.profiles = [Profile(id: "test", name: "测试", cmd: "", stop: "", env: [])]
        service.worktrees.append(Worktree(id: "feature", name: "开发", cwd: "/tmp"))
        var step = Step.command(cwd: "")
        precondition(FormValidation.step(step, services: [service]) == "请填写命令")
        step.cmd = "echo complete"
        precondition(FormValidation.step(step, services: [service]) == nil)
        step.cwdService = "deleted"
        precondition(FormValidation.step(step, services: [service]) != nil)
        for input in ["", "-1", "1a2", "0", "18446744073709551616"] {
            precondition(FormValidation.seconds(input, step: step) == nil, input)
        }
        precondition(FormValidation.seconds("120", step: step) == 120)
        step = .service(service.id)
        step.ready = .delay
        precondition(FormValidation.seconds("0", step: step) == 0)
        step.profile = "deleted"
        precondition(FormValidation.step(step, services: [service]) != nil)
        step.profile = "test"
        step.worktree = "deleted"
        precondition(FormValidation.step(step, services: [service]) != nil)
        step.worktree = "feature"
        precondition(FormValidation.step(step, services: [service]) == nil)
        precondition(FormValidation.step(step, services: []) != nil)
        print("端口、秒数与步骤校验通过")

        let completed = FlowBrief(state: .done, stage: 0, members: 0, matched: 0)
        precondition(completed.shown == .completed && completed.shown.label == "已完成")
        precondition(!completed.stops)
        precondition(FlowShown(state: .done, members: 2, matched: 2) == .started)
        precondition(FlowShown(state: .done, members: 2, matched: 1) == .partial)
        precondition(FlowShown(state: .done, members: 2, matched: 0) == .stopped)
        print("工作流完成状态通过")

        let store = Store()
        store.services = [service]
        let wf = Workflow(id: "wf", name: "联调", color: "blue", stages: [Stage(id: "s", steps: [step])])
        store.workflows = [wf]
        precondition(store.deletionReferences(service, profile: "test").contains("工作流「联调」"))
        precondition(store.deletionReferences(service, worktree: "feature").contains("工作流「联调」"))
        precondition(store.deletionReferences(service, profile: "unused").isEmpty)
        precondition(store.deletionReferences(service, worktree: "unused").isEmpty)
        store.workflows = []
        service.profile = "test"
        precondition(store.deletionReferences(service, profile: "test") == ["当前启动方案"])
        var runtime = ServiceStatus.idle(service.id)
        runtime.state = .running
        runtime.profile = "test"
        runtime.worktree = "feature"
        runtime.launch = RunningLaunch(profile: "test", name: "启动时方案", cmd: "echo original", stop: "echo stop",
            env: [EnvVar(k: "MODE", v: "original")], worktree: "feature", cwd: "/tmp", port: 5173)
        store.status[service.id] = runtime
        precondition(store.deletionReferences(service, worktree: "feature").contains("正在运行的服务"))
        service.cmd = "echo edited"
        service.env = [EnvVar(k: "MODE", v: "edited")]
        service.port = 8080
        precondition(store.shownLaunch(service).cmd == "echo original")
        precondition(store.shownLaunch(service).env[0].v == "original")
        precondition(store.shownProfileName(service) == "启动时方案")
        precondition(store.configuredPort(service) == 5173)
        store.status[service.id] = .idle(service.id)
        precondition(store.shownLaunch(service).cmd == "echo edited")
        print("删除引用检查与启动快照通过")

        _ = NSApplication.shared
        let face = ChromeFaceView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        let idle = NSColor.gray.cgColor
        let hot = NSColor.blue.cgColor
        face.configure(path: UIIcon.plus, idle: idle, hot: hot, hover: NSColor.lightGray.cgColor)
        let glyph = face.layer!.sublayers!.first as! CAShapeLayer
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        face.mouseEntered(with: event)
        precondition(glyph.strokeColor == hot)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
        precondition(glyph.strokeColor == idle)
        precondition(face.layer!.backgroundColor == nil)
        print("菜单关闭后按钮高亮恢复通过")
    }
}
