import SwiftUI

/// 工作流的运行页：各阶段的进度、每一步的结果与运行记录
struct WorkflowDetail: View {
    let onEdit: (Workflow) -> Void
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme
    /// 展开了输出的命令步骤
    @State private var expanded: Set<String> = []

    var body: some View {
        if let wf = store.selectedWorkflow {
            let st = store.flow(wf.id)
            VStack(alignment: .leading, spacing: 0) {
                header(wf, st)
                    .padding(.horizontal, Chrome.gutter)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if st.state == .failed {
                            failureBanner(wf, st)
                                .padding(.bottom, 12)
                        }
                        stats(wf, st)
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 0) {
                                sectionTitle("阶段")
                                if wf.stages.isEmpty {
                                    placeholder("还没有步骤，点右上角的编辑按钮添加")
                                }
                                ForEach(Array(wf.stages.enumerated()), id: \.element.id) { i, stage in
                                    stageBlock(st, index: i, stage: stage, last: i == wf.stages.count - 1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 0) {
                                sectionTitle("运行记录")
                                events(st)
                            }
                            .frame(width: 286)
                        }
                    }
                    .padding(.horizontal, Chrome.gutter)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.never)
                .edgeFade()
            }
        } else {
            Color.clear
        }
    }

    // MARK: 头部

    private func header(_ wf: Workflow, _ st: WorkflowStatus) -> some View {
        HStack(spacing: 13) {
            ChromeButton(path: UIIcon.back, help: "返回", tint: theme.blue) {
                store.back()
            }

            FlowBadge(side: 42, glyph: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(wf.name)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .lineBox(22)
                HStack(spacing: 7) {
                    FlowDot(shown: shown(st))
                    Text(shown(st).label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(theme.text(shown(st)))
                    Text(metaLine(wf, st))
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            HStack(spacing: 8) {
                switch shown(st) {
                case .running:
                    action("停止", icon: UIIcon.stop, primary: false) { store.stopWorkflow(wf.id) }
                case .failed:
                    action("重新运行", icon: UIIcon.restart, primary: true) { store.startWorkflow(wf.id) }
                    action("停止工作流", icon: UIIcon.stop, primary: false) { store.stopWorkflow(wf.id) }
                case .started, .partial:
                    action("停止", icon: UIIcon.stop, primary: false) { store.stopWorkflow(wf.id) }
                    ChromeButton(path: UIIcon.restart, help: "重新运行") { store.startWorkflow(wf.id) }
                case .ready, .partlyReady, .stopped, .idle:
                    action("启动", icon: UIIcon.play, primary: true) { store.startWorkflow(wf.id) }
                }
                ChromeButton(path: UIIcon.edit, help: "编辑工作流") { onEdit(wf) }
            }
        }
        .padding(.top, Chrome.headerTop)
        .padding(.bottom, 12)
        .padding(.horizontal, 2)
    }

    /// 启动类按钮蓝底，停止类按钮红底，与服务的启停按钮一致
    private func action(
        _ title: String, icon: String, primary: Bool, run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Glyph(path: icon, lineWidth: 2)
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(primary ? theme.blue : theme.red, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(Press(scale: 0.97))
    }

    private func shown(_ st: WorkflowStatus) -> FlowShown { st.brief.shown }

    private func metaLine(_ wf: Workflow, _ st: WorkflowStatus) -> String {
        let total = wf.stages.count
        switch st.state {
        case .running:
            return "阶段 \(st.stage + 1)/\(total) · 已用时 \(Fmt.duration(st.elapsed))"
        case .failed:
            return "停在阶段 \(st.stage + 1) · 用时 \(Fmt.duration(st.elapsed))"
        default:
            return "\(total) 个阶段 · \(st.matched)/\(st.members) 个服务运行中"
        }
    }

    private func failureBanner(_ wf: Workflow, _ st: WorkflowStatus) -> some View {
        let failedService = wf.steps.first {
            $0.kind == .service && st.step($0.id).state == .failed
        }?.service
        var notes: [String] = []
        if st.stage + 1 < wf.stages.count { notes.append("后续阶段未执行") }
        // 等端口超时的服务同样没有被停止
        let executed = wf.stages.prefix(st.stage + 1).flatMap(\.steps)
        let running = { (state: StepState) in
            executed
                .filter { $0.kind == .service && st.step($0.id).state == state }
                .filter { store.brief($0.service).state == .running }
                .compactMap { store.service($0.service)?.name }
                .joined(separator: "、")
        }
        let kept = running(.done)
        if !kept.isEmpty { notes.append("已就绪的 \(kept) 保持运行") }
        let unready = running(.failed)
        if !unready.isEmpty { notes.append("未就绪的 \(unready) 仍在运行") }

        return HStack(spacing: 10) {
            Glyph(path: UIIcon.warn, lineWidth: 2)
                .foregroundStyle(theme.redTx)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(st.message.isEmpty ? "阶段 \(st.stage + 1) 失败" : st.message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.redTx)
                    .lineLimit(2)
                if !notes.isEmpty {
                    Text(notes.joined(separator: "；"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.ink2)
                }
            }
            Spacer(minLength: 8)
            if let sid = failedService {
                Button { openLog(sid) } label: {
                    Text("查看日志")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(theme.win, in: .rect(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7).strokeBorder(theme.sep, lineWidth: 0.5)
                        }
                }
                .buttonStyle(Press(scale: 0.97))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(theme.red.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(theme.red.opacity(0.2), lineWidth: 0.5)
        }
    }

    private func openLog(_ sid: String) {
        store.logMode = .this
        store.drawerOpen = true
        store.open(sid)
    }

    // MARK: 指标

    private func stats(_ wf: Workflow, _ st: WorkflowStatus) -> some View {
        let commands = wf.steps.filter { $0.kind == .command }
        let commandsDone = commands.filter { st.step($0.id).state == .done }.count
        let items: [(String, String, String, Color)] = [
            (
                "状态", shown(st).label,
                st.state == .running
                    ? "正在执行阶段 \(st.stage + 1)/\(wf.stages.count)"
                    : st.state == .failed ? "停在阶段 \(st.stage + 1)" : "共 \(wf.stages.count) 个阶段",
                theme.text(shown(st))
            ),
            (
                st.state == .running ? "已用时" : "上次用时",
                st.started == 0 ? "—" : Fmt.duration(st.elapsed),
                st.started == 0 ? "本次启动后尚未运行" : "开始于 \(Fmt.clock(st.started))",
                theme.ink
            ),
            ("服务", "\(st.matched) / \(st.members)", "按本工作流方案运行", theme.ink),
            (
                "命令", "\(commandsDone) / \(commands.count)",
                commands.isEmpty ? "没有命令步骤" : "本次运行完成的命令", theme.ink
            ),
        ]
        return Card {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    if i > 0 {
                        Rectangle().fill(theme.sep).frame(width: 0.5)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.0)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink3)
                        Text(item.1)
                            .font(.system(size: 18, weight: .semibold).monospacedDigit())
                            .tracking(-0.25)
                            .foregroundStyle(item.3)
                            .lineLimit(1)
                            .lineBox(18)
                        Text(item.2)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.ink3)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: 阶段

    private enum Mark {
        case pending, running, done, failed, skipped
        /// 部分步骤完成，其余没有执行
        case partial
        /// 执行过的服务已停止或换了方案
        case halted
    }

    /// 由各步骤的状态推出，步骤状态已按服务此刻的进程换算
    private func mark(_ st: WorkflowStatus, index: Int, stage: Stage) -> Mark {
        let states = stage.steps.map { st.step($0.id).state }
        if states.contains(.failed) { return .failed }
        if states.contains(.running) { return .running }
        if states.contains(.stopped) { return .halted }
        if !states.isEmpty, states.allSatisfy({ $0 == .done }) { return .done }
        if states.contains(.done) { return .partial }
        if states.contains(.skipped) { return .skipped }
        if st.state == .running, st.stage == index { return .running }
        return .pending
    }

    private func stageBlock(_ st: WorkflowStatus, index: Int, stage: Stage, last: Bool) -> some View {
        let m = mark(st, index: index, stage: stage)
        let longest = stage.steps.map { st.step($0.id).elapsed }.max() ?? 0
        let summary: (String, Color) =
            switch m {
            case .done: (longest > 0 ? "完成 · \(Fmt.duration(longest))" : "完成", theme.greenTx)
            case .partial: ("部分完成", theme.ink2)
            case .running: ("进行中", theme.orangeTx)
            case .failed: ("失败 · \(Fmt.duration(longest))", theme.redTx)
            case .skipped: (st.state == .stopped ? "已停止" : "未执行", theme.ink3)
            case .pending: ("", theme.ink3)
            case .halted:
                (
                    stage.steps.allSatisfy { $0.kind == .command || st.step($0.id).state == .stopped }
                        ? "服务已停止" : "部分服务已停止",
                    theme.ink3
                )
            }
        let dim = m == .skipped || m == .pending && st.state != .idle

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("阶段 \(index + 1)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(dim ? theme.ink3 : theme.ink)
                if stage.steps.count > 1 {
                    SmallTag(text: "同时开始")
                }
                Spacer(minLength: 8)
                Text(summary.0)
                    .font(.system(size: 11.5))
                    .foregroundStyle(summary.1)
            }
            .frame(height: 18)

            Card {
                VStack(spacing: 0) {
                    ForEach(Array(stage.steps.enumerated()), id: \.element.id) { i, step in
                        stepRow(step, st.step(step.id), first: i == 0, dim: dim)
                    }
                }
            }
            .overlay {
                if m == .running || m == .failed {
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder((m == .failed ? theme.red : theme.orange).opacity(0.45), lineWidth: 0.5)
                }
            }
        }
        .padding(.leading, 30)
        .padding(.bottom, last ? 0 : 16)
        // 节点与竖线画在左侧留白里，竖线随本阶段的高度伸展
        .overlay(alignment: .topLeading) {
            VStack(spacing: 4) {
                marker(m)
                if !last {
                    Capsule()
                        .fill(m == .done ? theme.green.opacity(0.45) : theme.sep)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 18)
        }
    }

    @ViewBuilder
    private func marker(_ m: Mark) -> some View {
        switch m {
        case .done:
            Circle().fill(theme.green)
                .frame(width: 18, height: 18)
                .overlay {
                    Glyph(path: UIIcon.check, lineWidth: 3.2).foregroundStyle(.white).frame(width: 11, height: 11)
                }
        case .failed:
            Circle().fill(theme.red)
                .frame(width: 18, height: 18)
                .overlay {
                    Glyph(path: UIIcon.xmark, lineWidth: 3.4).foregroundStyle(.white).frame(width: 10, height: 10)
                }
        case .running:
            Circle().strokeBorder(theme.orange.opacity(0.3), lineWidth: 2.4)
                .frame(width: 18, height: 18)
                .overlay { Dot(phase: .starting, size: 7) }
        case .skipped, .pending:
            Circle().strokeBorder(theme.sep, lineWidth: 2)
                .frame(width: 18, height: 18)
        case .partial:
            Circle().strokeBorder(theme.green, lineWidth: 2.4)
                .frame(width: 18, height: 18)
        case .halted:
            stoppedMark(side: 18)
        }
    }

    private func stoppedMark(side: CGFloat) -> some View {
        Circle().fill(theme.dim)
            .frame(width: side, height: side)
            .overlay {
                Glyph(path: UIIcon.stop, lineWidth: 2.4).foregroundStyle(.white)
                    .frame(width: side * 2 / 3, height: side * 2 / 3)
            }
    }

    private func stepRow(_ step: Step, _ s: StepStatus, first: Bool, dim: Bool) -> some View {
        let svc = store.service(step.service)
        let isOpen = expanded.contains(step.id)
        let opens = step.kind == .command || svc != nil
        return VStack(alignment: .leading, spacing: 0) {
            if !first {
                Rectangle().fill(theme.sep2).frame(height: 0.5)
            }
            // 展开的输出与步骤行共用一块悬停底色，只有步骤行响应点击
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    stepIcon(step, svc, dim: dim)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(title(step, svc))
                                .font(.system(size: 13))
                                .foregroundStyle(dim ? theme.ink3 : theme.ink)
                                .lineLimit(1)
                                .layoutPriority(1)
                            if step.kind == .command {
                                SmallTag(text: step.cmd, mono: true, fixed: false)
                            } else if let svc, !svc.profiles.isEmpty {
                                SmallTag(text: step.profile.isEmpty ? "跟随当前" : svc.profileName(step.profile))
                            }
                        }
                        HStack(spacing: 6) {
                            Text(subtitle(step))
                                .font(.system(size: 11))
                                .foregroundStyle(theme.ink3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if step.kind == .command, [.running, .done, .failed].contains(s.state) {
                                link(isOpen ? "收起输出" : "查看输出") {
                                    if isOpen { expanded.remove(step.id) } else { expanded.insert(step.id) }
                                }
                            } else if step.kind == .service, s.state == .failed, svc != nil {
                                link("查看日志") { openLog(step.service) }
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    Text(result(s))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(resultColor(s))
                        .lineLimit(1)
                    resultIcon(s)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(.rect)
                .pointerCursor(opens ? .pointingHand : nil)
                .onTapGesture { openStep(step, svc) }
                .help(step.kind == .command ? "展开或收起输出" : svc == nil ? "" : "打开服务详情")

                if isOpen {
                    output(step)
                }
            }
            .background(s.state == .failed ? theme.red.opacity(0.05) : .clear)
            .hoverHighlight(cursor: nil)
        }
    }

    /// 服务步骤进入服务详情，命令步骤展开或收起输出
    private func openStep(_ step: Step, _ svc: ServiceConfig?) {
        switch step.kind {
        case .service:
            if let svc { store.open(svc.id) }
        case .command:
            if expanded.contains(step.id) { expanded.remove(step.id) } else { expanded.insert(step.id) }
        }
    }

    @ViewBuilder
    private func stepIcon(_ step: Step, _ svc: ServiceConfig?, dim: Bool) -> some View {
        if step.kind == .command {
            RoundedRectangle(cornerRadius: 5.4)
                .fill(Color(hex: 0x8E8E93))
                .frame(width: 20, height: 20)
                .overlay {
                    Glyph(path: UIIcon.terminal, lineWidth: 2.2).foregroundStyle(.white).frame(width: 12, height: 12)
                }
                .opacity(dim ? 0.45 : 1)
        } else {
            IconBadge(ic: svc?.ic ?? "chip", side: 20, glyph: 12, phase: dim ? .stopped : .running)
                .overlay(alignment: .bottomTrailing) {
                    // 服务的实时状态，被别的工作流或手动拉起时也看得出来
                    if let svc {
                        Dot(phase: store.phase(svc.id), size: 6)
                            .padding(1.5)
                            .background(Circle().fill(theme.card))
                            .offset(x: 3, y: 3)
                    }
                }
        }
    }


    private func title(_ step: Step, _ svc: ServiceConfig?) -> String {
        switch step.kind {
        case .service: svc?.name ?? "已删除的服务"
        case .command: step.name.isEmpty ? "命令" : step.name
        }
    }

    private func subtitle(_ step: Step) -> String {
        switch (step.kind, step.ready) {
        case (.command, _):
            let dir = step.cwd.isEmpty ? "~" : step.cwd
            return "\(dir) · 超时 \(step.seconds) 秒"
        case (.service, .port):
            return "就绪条件：端口开始监听 · 超时 \(step.seconds) 秒"
        case (.service, .delay):
            return "就绪条件：启动后等待 \(step.seconds) 秒"
        }
    }

    /// 进行中与完成只报时长，失败与服务停止写明原因；端口、退出码等明细在运行记录里。
    /// 不是本次运行完成的步骤耗时为 0，不报时长
    private func result(_ s: StepStatus) -> String {
        switch s.state {
        case .pending, .skipped: ""
        case .running: Fmt.duration(s.elapsed)
        case .done: s.elapsed > 0 ? Fmt.duration(s.elapsed) : ""
        case .failed, .stopped: s.detail
        }
    }

    private func resultColor(_ s: StepStatus) -> Color {
        switch s.state {
        case .running: theme.orangeTx
        case .failed: theme.redTx
        case .done: theme.greenTx
        case .pending, .skipped, .stopped: theme.ink3
        }
    }

    @ViewBuilder
    private func resultIcon(_ s: StepStatus) -> some View {
        switch s.state {
        case .done:
            Circle().fill(theme.green)
                .frame(width: 15, height: 15)
                .overlay {
                    Glyph(path: UIIcon.check, lineWidth: 3.2).foregroundStyle(.white).frame(width: 9, height: 9)
                }
        case .failed:
            Circle().fill(theme.red)
                .frame(width: 15, height: 15)
                .overlay {
                    Glyph(path: UIIcon.xmark, lineWidth: 3.4).foregroundStyle(.white).frame(width: 8, height: 8)
                }
        case .running:
            SpinGlyph(path: UIIcon.restart, color: theme.orange, lineWidth: 2.2, spinning: true)
                .frame(width: 14, height: 14)
        case .stopped:
            stoppedMark(side: 15)
        case .pending, .skipped:
            EmptyView()
        }
    }

    private func link(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(theme.blueTx)
        }
        .buttonStyle(Press(scale: 0.97))
    }

    /// 命令步骤的输出，来源 id 就是步骤 id
    private func output(_ step: Step) -> some View {
        let lines = store.logs.filter { $0.sid == step.id }.suffix(200)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if lines.isEmpty {
                    Text("没有输出")
                        .foregroundStyle(theme.ink3)
                }
                ForEach(lines) { l in
                    Text(l.txt)
                        .foregroundStyle(l.lvl == "ERROR" ? theme.redTx : l.lvl == "WARN" ? theme.orangeTx : theme.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(9)
        }
        .frame(maxHeight: 180)
        .background(theme.win)
        .overlay {
            RoundedRectangle(cornerRadius: 9).strokeBorder(theme.sep, lineWidth: 0.5)
        }
        .clipShape(.rect(cornerRadius: 9))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: 运行记录

    private func events(_ st: WorkflowStatus) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                if st.events.isEmpty {
                    Text("本次启动后尚未运行")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                ForEach(Array(st.events.enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(eventColor(e.kind))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(e.text)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.clock(e.ts))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.ink3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func eventColor(_ kind: String) -> Color {
        switch kind {
        case "start": theme.blue
        case "done": theme.green
        case "error": theme.red
        default: theme.dim
        }
    }

    // MARK: 小件

    private func sectionTitle(_ text: String) -> some View {
        SectionLabel(text: text)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .padding(.horizontal, 4)
    }

    private func placeholder(_ text: String) -> some View {
        Card {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.ink3)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
