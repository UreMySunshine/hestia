import AppKit
import SwiftUI

/// 编辑工作流：阶段依次执行，每个阶段里放若干服务或命令步骤
struct WorkflowForm: View {
    let draft: Workflow
    let isNew: Bool
    let onSave: (Workflow) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    @State private var name = ""
    @State private var stages: [Stage] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        caption("名称")
                        Field(placeholder: "例如 PC 联调", text: $name)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        caption("阶段")
                            .padding(.bottom, 8)
                        ForEach(Array(stages.enumerated()), id: \.element.id) { i, stage in
                            if i > 0 {
                                Glyph(path: UIIcon.arrowDown, lineWidth: 2)
                                    .foregroundStyle(theme.ink3)
                                    .frame(width: 14, height: 14)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 26)
                            }
                            stageCard(index: i, stage: stage)
                        }
                        addStageButton
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
            .edgeFade()
            footer
        }
        .frame(width: 600, height: 720)
        .background(theme.win)
        .onAppear {
            name = draft.name
            stages = draft.stages.isEmpty ? [.blank()] : draft.stages
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isNew ? "新建工作流" : "编辑工作流")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(theme.ink)
                .lineBox(17)
            Text("阶段按顺序执行；同一阶段内的步骤同时开始，全部完成后进入下一阶段")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    // MARK: 阶段

    private func stageCard(index: Int, stage: Stage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("阶段 \(index + 1)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                if stage.steps.count > 1 {
                    Text("\(stage.steps.count) 个步骤同时开始")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.ink3)
                }
                Spacer()
                iconButton(UIIcon.trash, help: "删除阶段") {
                    stages.removeAll { $0.id == stage.id }
                }
            }

            if stage.steps.isEmpty {
                Text("空阶段会被忽略，添加服务或命令")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.ink3)
            }
            ForEach(stage.steps) { step in
                stepCard(stageID: stage.id, stageIndex: index, step: step)
            }

            HStack(spacing: 6) {
                PopUpMenu(entries: { serviceChoices(stageID: stage.id) }) {
                    smallLabel("服务")
                }
                .buttonStyle(Press(scale: 0.96))
                Button { append(Step.command(cwd: ""), to: stage.id) } label: {
                    smallLabel("命令")
                }
                .buttonStyle(Press(scale: 0.96))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.fill.opacity(0.6), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(theme.sep2, lineWidth: 0.5)
        }
    }

    private var addStageButton: some View {
        Button {
            stages.append(.blank())
        } label: {
            HStack(spacing: 6) {
                Glyph(path: UIIcon.plus, lineWidth: 2.2)
                    .frame(width: 12, height: 12)
                Text("添加阶段").font(.system(size: 12.5))
            }
            .foregroundStyle(theme.ink2)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(theme.sep, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(Press(scale: 0.98))
    }

    // MARK: 步骤

    private func stepCard(stageID: String, stageIndex: Int, step: Step) -> some View {
        let b = stepBinding(stageID: stageID, stepID: step.id)
        return VStack(alignment: .leading, spacing: 7) {
            switch step.kind {
            case .service: serviceStep(b, stageID: stageID)
            case .command: commandStep(b, stageID: stageID)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.win, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(theme.sep, lineWidth: 0.5)
        }
        .contextMenu {
            ForEach(Array(stages.enumerated()), id: \.element.id) { j, target in
                if j != stageIndex {
                    Button("移到阶段 \(j + 1)") { move(step.id, from: stageID, to: target.id) }
                }
            }
            Button("移到新阶段") {
                let fresh = Stage.blank()
                stages.append(fresh)
                move(step.id, from: stageID, to: fresh.id)
            }
            Divider()
            Button("删除", role: .destructive) { remove(step.id, from: stageID) }
        }
    }

    @ViewBuilder
    private func serviceStep(_ b: Binding<Step>, stageID: String) -> some View {
        let step = b.wrappedValue
        let svc = store.service(step.service)
        HStack(spacing: 8) {
            IconBadge(ic: svc?.ic ?? "chip", side: 18, glyph: 11, phase: svc == nil ? .stopped : .running)
            PopUpMenu(entries: { serviceChoices(for: b) }) {
                chip(svc?.name ?? "已删除的服务")
            }
            .buttonStyle(Press(scale: 0.97))
            if let svc {
                if svc.profiles.isEmpty {
                    Text("仅默认方案")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.ink3)
                } else {
                    caption("方案")
                    PopUpMenu(entries: { profileChoices(for: b, svc) }) {
                        chip(step.profile.isEmpty ? "跟随当前" : svc.profileName(step.profile))
                    }
                    .buttonStyle(Press(scale: 0.97))
                }
            }
            Spacer(minLength: 0)
            iconButton(UIIcon.trash, help: "删除步骤") { remove(step.id, from: stageID) }
        }
        HStack(spacing: 6) {
            fieldLabel("就绪")
            PopUpMenu(entries: { readyChoices(for: b) }) {
                chip(step.ready.label)
            }
            .buttonStyle(Press(scale: 0.97))
            switch step.ready {
            case .port:
                caption("超时").padding(.leading, 6)
                secondsField(b)
                caption("秒")
            case .delay:
                secondsField(b)
                caption("秒，期间进程退出视为失败")
            }
        }
        .padding(.leading, 26)
    }

    @ViewBuilder
    private func commandStep(_ b: Binding<Step>, stageID: String) -> some View {
        let step = b.wrappedValue
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4.9)
                .fill(Color(hex: 0x8E8E93))
                .frame(width: 18, height: 18)
                .overlay {
                    Glyph(path: UIIcon.terminal, lineWidth: 2.2).foregroundStyle(.white).frame(width: 11, height: 11)
                }
            caption("名称")
            Field(placeholder: "例如 安装依赖", text: b.name)
            iconButton(UIIcon.trash, help: "删除步骤") { remove(step.id, from: stageID) }
        }
        HStack(spacing: 6) {
            fieldLabel("命令")
            Field(placeholder: "pnpm i", text: b.cmd, mono: true)
        }
        .padding(.leading, 26)
        HStack(spacing: 6) {
            fieldLabel("目录")
            Field(placeholder: "~/dev/my-project", text: b.cwd, mono: true)
            Button { pickFolder(b) } label: {
                Glyph(path: UIIcon.folder, lineWidth: 1.8)
                    .foregroundStyle(theme.ink2)
                    .frame(width: 13, height: 13)
                    .frame(width: 30, height: 31)
                    .background(theme.fill, in: .rect(cornerRadius: 7))
            }
            .buttonStyle(Press())
            .help("选择目录")
            caption("超时").padding(.leading, 6)
            secondsField(b)
            caption("秒")
        }
        .padding(.leading, 26)
        Group {
            if step.cmd.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("未填写命令，保存时会忽略这一步")
                    .foregroundStyle(theme.orangeTx)
            } else {
                Text("退出码为 0 视为完成")
                    .foregroundStyle(theme.ink3)
            }
        }
        .font(.system(size: 11))
        .padding(.leading, 62)
    }

    // MARK: 菜单

    private func serviceChoices(stageID: String) -> [MenuEntry] {
        guard !store.services.isEmpty else {
            return [.item("还没有服务", enabled: false) {}]
        }
        return store.services.map { svc in
            .item(svc.name) { append(Step.service(svc.id), to: stageID) }
        }
    }

    private func serviceChoices(for b: Binding<Step>) -> [MenuEntry] {
        store.services.map { svc in
            .item(svc.name, checked: b.wrappedValue.service == svc.id) {
                guard b.wrappedValue.service != svc.id else { return }
                b.wrappedValue.service = svc.id
                b.wrappedValue.profile = ""
            }
        }
    }

    private func profileChoices(for b: Binding<Step>, _ svc: ServiceConfig) -> [MenuEntry] {
        let chosen = b.wrappedValue.profile
        var out: [MenuEntry] = [
            .item(
                "跟随当前方案", subtitle: "现为\(svc.profileName(svc.profileID(svc.profile)))",
                checked: chosen.isEmpty
            ) { b.wrappedValue.profile = "" },
            .separator,
        ]
        for id in [defaultProfile] + svc.profiles.map(\.id) {
            out.append(
                .item(svc.profileName(id), subtitle: svc.profileSummary(id), checked: chosen == id) {
                    b.wrappedValue.profile = id
                })
        }
        return out
    }

    private func readyChoices(for b: Binding<Step>) -> [MenuEntry] {
        ReadyKind.allCases.map { kind in
            .item(
                kind.label,
                subtitle: kind == .port ? "进程树开始监听任一端口，超时视为失败" : "启动后等待固定秒数",
                checked: b.wrappedValue.ready == kind
            ) {
                guard b.wrappedValue.ready != kind else { return }
                b.wrappedValue.ready = kind
                b.wrappedValue.seconds = kind == .port ? 120 : 5
            }
        }
    }

    // MARK: 数据

    /// 按 id 取步骤的绑定。步骤被删掉后旧的绑定只会读到原值，不会越界
    private func stepBinding(stageID: String, stepID: String) -> Binding<Step> {
        Binding(
            get: {
                stages.first { $0.id == stageID }?.steps.first { $0.id == stepID }
                    ?? Step.command(cwd: "")
            },
            set: { value in
                guard let i = stages.firstIndex(where: { $0.id == stageID }),
                    let j = stages[i].steps.firstIndex(where: { $0.id == stepID })
                else { return }
                stages[i].steps[j] = value
            })
    }

    private func append(_ step: Step, to stageID: String) {
        guard let i = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[i].steps.append(step)
    }

    private func remove(_ stepID: String, from stageID: String) {
        guard let i = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[i].steps.removeAll { $0.id == stepID }
    }

    private func move(_ stepID: String, from: String, to: String) {
        guard let i = stages.firstIndex(where: { $0.id == from }),
            let step = stages[i].steps.first(where: { $0.id == stepID }),
            let j = stages.firstIndex(where: { $0.id == to })
        else { return }
        stages[i].steps.removeAll { $0.id == stepID }
        stages[j].steps.append(step)
    }

    private func pickFolder(_ b: Binding<Step>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "选择工作目录"
        if let dir = Paths.expand(b.wrappedValue.cwd) { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        b.wrappedValue.cwd = Paths.abbreviate(url)
    }

    private func save() {
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespaces) }
        var out = draft
        out.name = trim(name).isEmpty ? "未命名工作流" : trim(name)
        out.stages = stages.compactMap { stage in
            var stage = stage
            stage.steps = stage.steps.compactMap { step in
                var step = step
                step.name = trim(step.name)
                step.cmd = trim(step.cmd)
                step.cwd = trim(step.cwd)
                switch step.kind {
                case .service: return step.service.isEmpty ? nil : step
                case .command: return step.cmd.isEmpty ? nil : step
                }
            }
            return stage.steps.isEmpty ? nil : stage
        }
        onSave(out)
        dismiss()
    }

    // MARK: 小件

    private var footer: some View {
        HStack(spacing: 9) {
            if !isNew {
                Button {
                    onDelete()
                    dismiss()
                } label: {
                    Text("删除工作流")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.redTx)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(theme.red.opacity(0.08), in: .rect(cornerRadius: 8))
                }
                .buttonStyle(Press(scale: 0.97))
            }
            Spacer()
            Button { dismiss() } label: {
                Text("取消")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(theme.fill2, in: .rect(cornerRadius: 8))
            }
            .buttonStyle(Press(scale: 0.97))
            .keyboardShortcut(.cancelAction)

            Button(action: save) {
                Text("保存")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(theme.blue, in: .rect(cornerRadius: 8))
            }
            .buttonStyle(Press(scale: 0.97))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.sep).frame(height: 0.5)
        }
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 12.5))
                .lineLimit(1)
            Glyph(path: UIIcon.chevronUpDown, lineWidth: 2.4)
                .frame(width: 10, height: 10)
        }
        .foregroundStyle(theme.ink)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background(theme.fill2, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
    }

    private func smallLabel(_ text: String) -> some View {
        HStack(spacing: 5) {
            Glyph(path: UIIcon.plus, lineWidth: 2.2)
                .frame(width: 11, height: 11)
            Text(text).font(.system(size: 11.5))
        }
        .foregroundStyle(theme.ink2)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(theme.fill2, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
    }

    private func iconButton(_ path: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(path: path, lineWidth: 1.8)
                .foregroundStyle(theme.ink3)
                .frame(width: 13, height: 13)
                .frame(width: 26, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(Press())
        .help(help)
    }

    private func secondsField(_ b: Binding<Step>) -> some View {
        Field(
            placeholder: "0",
            text: Binding(
                get: { b.wrappedValue.seconds == 0 ? "" : String(b.wrappedValue.seconds) },
                set: { b.wrappedValue.seconds = UInt64($0.filter(\.isNumber)) ?? 0 }),
            mono: true
        )
        .frame(width: 60)
    }

    private func fieldLabel(_ text: String) -> some View {
        caption(text).frame(width: 30, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(theme.ink3)
    }
}
