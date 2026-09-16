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

    private struct EnvRow: Identifiable {
        let id = UUID()
        var k: String
        var v: String
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identity
                    kinds
                    command
                    envSection
                    checks
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)
            }
            footer
        }
        .frame(width: 600, height: 660)
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

    private var command: some View {
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
            labeled("启动命令") { Field(placeholder: "pnpm dev --port 5173", text: $cmd, mono: true) }
            labeled("停止命令") { Field(placeholder: "留空则向进程组发信号", text: $stop, mono: true) }

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

    private var envSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("环境变量")
            ForEach($env) { $row in
                HStack(spacing: 8) {
                    Field(placeholder: "KEY", text: $row.k, mono: true)
                        .frame(width: 190)
                    Field(placeholder: "value", text: $row.v, mono: true)
                    Button {
                        env.removeAll { $0.id == row.id }
                    } label: {
                        Glyph(path: UIIcon.trash, lineWidth: 1.8)
                            .foregroundStyle(theme.ink3)
                            .frame(width: 13, height: 13)
                            .frame(width: 26, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(Press())
                    .help("删除")
                }
            }
            Button {
                env.append(EnvRow(k: "", v: ""))
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

    private var checkList: [Check] {
        let portNumber = UInt16(port.trimmingCharacters(in: .whitespaces))
        let dir = Paths.expand(cwd)
        return [
            Check(
                ok: !cmd.trimmingCharacters(in: .whitespaces).isEmpty,
                label: cmd.isEmpty ? "请填写启动命令" : "启动命令已填写",
                color: cmd.isEmpty ? theme.orangeTx : theme.greenTx),
            Check(
                ok: !stop.trimmingCharacters(in: .whitespaces).isEmpty,
                label: stop.isEmpty ? "未填停止命令，将向进程组发 SIGTERM" : "停止命令已填写",
                color: stop.isEmpty ? theme.orangeTx : theme.greenTx),
            portCheck(portNumber),
            Check(
                ok: cwd.isEmpty || dir != nil,
                label: cwd.isEmpty
                    ? "未填工作目录，默认在 ~ 下启动"
                    : (dir != nil ? "工作目录可访问" : "工作目录不存在"),
                color: cwd.isEmpty ? theme.ink3 : (dir != nil ? theme.greenTx : theme.orangeTx)),
        ]
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
        out.name = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "未命名服务" : name.trimmingCharacters(in: .whitespaces)
        out.proj = proj.trimmingCharacters(in: .whitespaces)
        out.ic = kind
        out.cwd = cwd.trimmingCharacters(in: .whitespaces)
        out.cmd = cmd.trimmingCharacters(in: .whitespaces)
        out.stop = stop.trimmingCharacters(in: .whitespaces)
        out.port = UInt16(port.trimmingCharacters(in: .whitespaces)) ?? 0
        out.autoRestart = autoRestart
        out.env = env
            .filter { !$0.k.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { EnvVar(k: $0.k.trimmingCharacters(in: .whitespaces), v: $0.v) }
        onSave(out)
        dismiss()
    }

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
