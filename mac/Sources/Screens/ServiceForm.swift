import AppKit
import SwiftUI

struct ServiceForm: View {
    let draft: ServiceConfig
    let isNew: Bool
    let onSave: (ServiceConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var name = ""
    @State private var proj = ""
    @State private var kind = "web"
    @State private var cwd = ""
    @State private var cmd = ""
    @State private var stop = ""
    @State private var port = ""
    @State private var autoRestart = true
    @State private var env: [EnvRow] = []
    @State private var profiles: [ProfileRow] = []
    @State private var current = defaultProfile
    /// 正在编辑的方案
    @State private var tab = defaultProfile

    private struct EnvRow: Identifiable {
        let id = UUID()
        var k: String
        var v: String
    }

    private struct ProfileRow: Identifiable {
        let id: String
        var name: String
        var cmd: String
        var stop: String
        var env: [EnvRow]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identity
                    kinds
                    location
                    profileSection
                    checks
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
            .edgeFade()
            footer
        }
        .frame(width: 600, height: 720)
        .background(theme.win)
        .onAppear(perform: load)
    }

    private func load() {
        name = draft.name
        proj = draft.proj
        kind = draft.ic
        cwd = draft.cwd
        cmd = draft.cmd
        stop = draft.stop
        port = draft.port == 0 ? "" : String(draft.port)
        autoRestart = draft.autoRestart
        env = draft.env.map { EnvRow(k: $0.k, v: $0.v) }
        profiles = draft.profiles.map {
            ProfileRow(
                id: $0.id, name: $0.name, cmd: $0.cmd, stop: $0.stop,
                env: $0.env.map { EnvRow(k: $0.k, v: $0.v) })
        }
        current = draft.profileID(draft.profile)
        tab = defaultProfile
    }

    // MARK: 区块

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isNew ? "新建服务" : "编辑启动配置")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(theme.ink)
                .lineBox(17)
            Text("保存后可在服务列表一键启动")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            labeled("服务名称") { Field(placeholder: "例如 Web 前端", text: $name) }
            labeled("所属项目") { Field(placeholder: "例如 shop-frontend", text: $proj) }
        }
    }

    private var kinds: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("服务类型")
            HStack(spacing: 7) {
                ForEach(ServiceIcon.kinds, id: \.key) { k in
                    let on = kind == k.key
                    Button { kind = k.key } label: {
                        HStack(spacing: 7) {
                            Glyph(path: ServiceIcon.path(k.key))
                                .frame(width: 14, height: 14)
                            Text(k.label)
                                .font(.system(size: 12.5, weight: on ? .medium : .regular))
                        }
                        .foregroundStyle(on ? .white : theme.ink2)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(on ? theme.blue : theme.fill, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(Press(scale: 0.96))
                }
            }
        }
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                caption("工作目录")
                HStack(spacing: 8) {
                    Field(placeholder: "~/dev/my-project", text: $cwd, mono: true)
                    Button(action: pickFolder) {
                        Glyph(path: UIIcon.folder, lineWidth: 1.7)
                            .foregroundStyle(theme.ink2)
                            .frame(width: 15, height: 15)
                            .frame(width: 32, height: 31)
                            .background(theme.fill, in: .rect(cornerRadius: 7))
                    }
                    .buttonStyle(Press())
                    .help("选择目录")
                }
            }

            HStack(spacing: 12) {
                labeled("监听端口（可选）") { Field(placeholder: "5173", text: $port, mono: true) }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("崩溃后自动重启")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.ink)
                        Text("最多重试 5 次")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.ink3)
                    }
                    Spacer(minLength: 0)
                    Switch(isOn: $autoRestart)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(theme.fill, in: .rect(cornerRadius: 8))
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 启动方案

    private var tabOptions: [(value: String, label: String)] {
        [(defaultProfile, "默认")] + profiles.map { ($0.id, label($0)) }
    }

    private func label(_ p: ProfileRow) -> String {
        let n = trim(p.name)
        return n.isEmpty ? "未命名" : n
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                caption("启动方案")
                Spacer()
                if !profiles.isEmpty {
                    let name = profiles.first { $0.id == current }.map(label) ?? "默认"
                    Text("当前方案：\(name)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.ink3)
                }
            }
            HStack(spacing: 8) {
                if !profiles.isEmpty {
                    Segmented(options: tabOptions, selection: $tab)
                }
                Button(action: addProfile) {
                    HStack(spacing: 5) {
                        Glyph(path: UIIcon.plus, lineWidth: 2.2)
                            .frame(width: 11, height: 11)
                        Text("新建方案").font(.system(size: 12))
                    }
                    .foregroundStyle(theme.ink2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.fill, in: .rect(cornerRadius: 7))
                }
                .buttonStyle(Press(scale: 0.96))
                .help("同一目录下的另一套启动命令与环境变量")
            }

            VStack(alignment: .leading, spacing: 12) {
                if profiles.contains(where: { $0.id == tab }) {
                    profilePanel(profileBinding(tab))
                } else {
                    defaultPanel
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.fill.opacity(0.6), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(theme.sep2, lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private var defaultPanel: some View {
        labeled("启动命令") { Field(placeholder: "pnpm dev --port 5173", text: $cmd, mono: true) }
        labeled("停止命令") { Field(placeholder: "留空则向进程组发信号", text: $stop, mono: true) }
        envEditor($env, base: [], inherits: false)
    }

    @ViewBuilder
    private func profilePanel(_ p: Binding<ProfileRow>) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            labeled("方案名称") { Field(placeholder: "例如 test 环境", text: p.name) }
            Button { removeProfile(p.wrappedValue.id) } label: {
                Text("删除方案")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.redTx)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(theme.red.opacity(0.08), in: .rect(cornerRadius: 7))
            }
            .buttonStyle(Press(scale: 0.97))
        }
        labeled("启动命令") {
            Field(placeholder: inherit(cmd, fallback: "留空沿用默认"), text: p.cmd, mono: true)
        }
        labeled("停止命令") {
            Field(placeholder: inherit(stop, fallback: "留空沿用默认：向进程组发信号"), text: p.stop, mono: true)
        }
        envEditor(p.env, base: env, inherits: true)
    }

    private func inherit(_ value: String, fallback: String) -> String {
        let v = trim(value)
        return v.isEmpty ? fallback : "留空沿用默认：\(v)"
    }

    /// 按 id 取方案的绑定。删掉方案后旧的绑定取到的是空白占位，不会越界
    private func profileBinding(_ id: String) -> Binding<ProfileRow> {
        Binding(
            get: {
                profiles.first { $0.id == id }
                    ?? ProfileRow(id: id, name: "", cmd: "", stop: "", env: [])
            },
            set: { value in
                if let i = profiles.firstIndex(where: { $0.id == id }) { profiles[i] = value }
            })
    }

    /// 环境变量编辑。方案页里，默认方案中没有被覆盖的变量以只读行列出
    private func envEditor(_ rows: Binding<[EnvRow]>, base: [EnvRow], inherits: Bool) -> some View {
        let own = Set(rows.wrappedValue.map { trim($0.k) })
        let inherited = base.filter { !trim($0.k).isEmpty && !own.contains(trim($0.k)) }
        let baseValues = Dictionary(base.map { (trim($0.k), $0.v) }, uniquingKeysWith: { a, _ in a })

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                caption("环境变量")
                if inherits {
                    Text("同名覆盖默认方案，新名追加")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.ink3)
                }
            }

            ForEach(inherited) { row in
                HStack(spacing: 8) {
                    readOnly(Text(trim(row.k)))
                        .frame(width: 190)
                    readOnly(
                        HStack(spacing: 8) {
                            Text(row.v).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text("继承自默认")
                                .font(.system(size: 11))
                        })
                    Button {
                        rows.wrappedValue.append(EnvRow(k: trim(row.k), v: row.v))
                    } label: {
                        Text("覆盖")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.blueTx)
                            .frame(width: 34, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(Press())
                    .help("在本方案里改写这个变量")
                }
            }

            ForEach(rows) { $row in
                HStack(spacing: 8) {
                    Field(placeholder: "KEY", text: $row.k, mono: true)
                        .frame(width: 190)
                    Field(placeholder: "value", text: $row.v, mono: true)
                        .overlay(alignment: .trailing) {
                            if let b = baseValues[trim(row.k)] {
                                Text("默认为 \(b)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.ink3)
                                    .lineLimit(1)
                                    .frame(maxWidth: 140, alignment: .trailing)
                                    .padding(.trailing, 10)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button {
                        rows.wrappedValue.removeAll { $0.id == row.id }
                    } label: {
                        Glyph(path: UIIcon.trash, lineWidth: 1.8)
                            .foregroundStyle(theme.ink3)
                            .frame(width: 13, height: 13)
                            .frame(width: 34, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(Press())
                    .help("删除")
                }
                if !trim(row.k).isEmpty && row.v.isEmpty {
                    HStack(spacing: 6) {
                        Glyph(path: UIIcon.warn, lineWidth: 2)
                            .frame(width: 12, height: 12)
                        Text("值为空：会以空字符串传入，.env 文件里的同名值通常不再生效")
                            .font(.system(size: 11.5))
                    }
                    .foregroundStyle(theme.orangeTx)
                }
            }

            Button {
                rows.wrappedValue.append(EnvRow(k: "", v: ""))
            } label: {
                HStack(spacing: 6) {
                    Glyph(path: UIIcon.plus, lineWidth: 2)
                        .frame(width: 13, height: 13)
                    Text("添加变量").font(.system(size: 12.5))
                }
                .foregroundStyle(theme.ink2)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(theme.fill, in: .rect(cornerRadius: 7))
            }
            .buttonStyle(Press())
        }
    }

    private func readOnly(_ content: some View) -> some View {
        content
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(theme.ink3)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
            .background(theme.fill, in: .rect(cornerRadius: 7))
    }

    private func addProfile() {
        let id = UUID().uuidString
        profiles.append(ProfileRow(id: id, name: "方案 \(profiles.count + 1)", cmd: "", stop: "", env: []))
        tab = id
    }

    private func removeProfile(_ id: String) {
        tab = defaultProfile
        profiles.removeAll { $0.id == id }
        if current == id { current = defaultProfile }
    }

    private var checks: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(checkList.enumerated()), id: \.offset) { _, c in
                HStack(spacing: 9) {
                    Glyph(path: c.ok ? UIIcon.check : UIIcon.warn, lineWidth: 2.1)
                        .foregroundStyle(c.color)
                        .frame(width: 14, height: 14)
                    Text(c.label)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.fill, in: .rect(cornerRadius: 9))
    }

    private var footer: some View {
        HStack(spacing: 9) {
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

    // MARK: 校验

    private struct Check {
        var ok: Bool
        var label: String
        var color: Color
    }

    /// 命令类检查跟随当前标签页：方案页里留空的命令按沿用默认说明
    private var checkList: [Check] {
        let portNumber = UInt16(port.trimmingCharacters(in: .whitespaces))
        let dir = Paths.expand(cwd)
        let profile = profiles.first { $0.id == tab }
        return [
            cmdCheck(profile),
            stopCheck(profile),
            portCheck(portNumber),
            Check(
                ok: cwd.isEmpty || dir != nil,
                label: cwd.isEmpty
                    ? "未填工作目录，默认在 ~ 下启动"
                    : (dir != nil ? "工作目录可访问" : "工作目录不存在"),
                color: cwd.isEmpty ? theme.ink3 : (dir != nil ? theme.greenTx : theme.orangeTx)),
        ]
    }

    private func cmdCheck(_ p: ProfileRow?) -> Check {
        if let p, !trim(p.cmd).isEmpty {
            return Check(ok: true, label: "方案的启动命令已填写", color: theme.greenTx)
        }
        let base = trim(cmd)
        if base.isEmpty {
            return Check(
                ok: false, label: p == nil ? "请填写启动命令" : "请在默认方案里填写启动命令",
                color: theme.orangeTx)
        }
        return Check(
            ok: true, label: p == nil ? "启动命令已填写" : "启动命令沿用默认：\(base)",
            color: theme.greenTx)
    }

    private func stopCheck(_ p: ProfileRow?) -> Check {
        if let p, !trim(p.stop).isEmpty {
            return Check(ok: true, label: "方案的停止命令已填写", color: theme.greenTx)
        }
        let base = trim(stop)
        if base.isEmpty {
            return Check(ok: false, label: "未填停止命令，将向进程组发 SIGTERM", color: theme.orangeTx)
        }
        return Check(
            ok: true, label: p == nil ? "停止命令已填写" : "停止命令沿用默认：\(base)",
            color: theme.greenTx)
    }

    private func portCheck(_ p: UInt16?) -> Check {
        guard let p, p > 0 else {
            return Check(ok: false, label: "未配置端口，跳过端口核对", color: theme.ink3)
        }
        let free = Port.isFree(p)
        return Check(
            ok: free,
            label: free ? "端口 \(p) 当前空闲" : "端口 \(p) 已被占用",
            color: free ? theme.greenTx : theme.orangeTx)
    }

    // MARK: 动作

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "选择工作目录"
        if let dir = Paths.expand(cwd) { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cwd = Paths.abbreviate(url)
    }

    private func save() {
        var out = draft
        out.name = trim(name).isEmpty ? "未命名服务" : trim(name)
        out.proj = trim(proj)
        out.ic = kind
        out.cwd = trim(cwd)
        out.cmd = trim(cmd)
        out.stop = trim(stop)
        out.port = UInt16(trim(port)) ?? 0
        out.autoRestart = autoRestart
        out.env = clean(env)
        out.profiles = profiles.map {
            Profile(
                id: $0.id, name: trim($0.name).isEmpty ? "未命名方案" : trim($0.name),
                cmd: trim($0.cmd), stop: trim($0.stop), env: clean($0.env))
        }
        out.profile = profiles.contains { $0.id == current } ? current : defaultProfile
        onSave(out)
        dismiss()
    }

    private func clean(_ rows: [EnvRow]) -> [EnvVar] {
        rows.filter { !trim($0.k).isEmpty }.map { EnvVar(k: trim($0.k), v: $0.v) }
    }

    private func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

    // MARK: 小件

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(theme.ink3)
    }

    private func labeled(_ text: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            caption(text)
            content()
        }
    }
}

enum Paths {
    /// 展开 `~` 并确认目录存在，不存在时返回 nil
    static func expand(_ raw: String) -> URL? {
        let p = raw.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return nil }
        let expanded = (p as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue
        else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    /// 家目录下的路径写回 `~` 开头，配置换机器时仍可用
    static func abbreviate(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}

enum Port {
    /// 尝试独占绑定回环地址上的该端口，绑得上说明当前没人监听
    static func isFree(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return true }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) == 0 }
        }
        return ok
    }
}
