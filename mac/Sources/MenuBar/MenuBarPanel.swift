import AppKit
import SwiftUI

struct MenuBarPanel: View {
    /// 收起面板
    var dismiss: () -> Void = {}
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            totals

            if store.services.isEmpty {
                Text("还没有配置服务")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(store.services) { svc in
                            row(svc)
                        }
                    }
                }
                // 接了鼠标时 .hidden 仍会显示滚动条，.never 才彻底去掉
                .scrollIndicators(.never)
                .edgeFade()
                .frame(maxHeight: 242)
            }

            footer
        }
        .padding(8)
        .frame(width: 296)
    }

    /// 点标题行打开主窗口并收起面板
    private var header: some View {
        HStack(spacing: 8) {
            if let img = NSImage(named: "app-icon") {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(.rect(cornerRadius: 5))
            }
            Text("Hestia")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.ink)
            Spacer()
            Text("\(store.runningCount)/\(store.services.count) 运行中")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(theme.ink3)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .contentShape(.rect)
        .hoverHighlight(radius: 7)
        .onTapGesture { openMain() }
        .help("打开主窗口")
        .padding(.bottom, 2)
    }

    /// CPU 折算成占整机的比例
    private var totals: some View {
        HStack(spacing: 8) {
            tile("CPU", "\(Int((store.totalCpu / Double(max(1, store.cores))).rounded()))%")
            tile("内存", String(format: "%.1fG", store.totalMem / 1024))
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 8)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.ink3)
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.fill, in: .rect(cornerRadius: 8))
    }

    private func row(_ svc: ServiceConfig) -> some View {
        let st = store.status(svc.id)
        let phase = store.phase(svc.id)
        return HStack(spacing: 9) {
            Dot(phase: phase)
            Text(svc.name)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(String(format: "%.1f%%", st.cpu))
                .font(.system(size: 11, design: .monospaced).monospacedDigit())
                .foregroundStyle(theme.ink3)
            RunButton(phase: phase, side: 25, height: 22) { store.toggle(svc.id) }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .contentShape(.rect)
        .hoverHighlight(radius: 7)
        .onTapGesture {
            store.open(svc.id)
            openMain()
        }
    }

    private func openMain() {
        dismiss()
        showMainWindow()
    }

    private var footer: some View {
        VStack(spacing: 7) {
            Rectangle().fill(theme.sep).frame(height: 0.5)
            HStack(spacing: 7) {
                Button { store.startAll() } label: {
                    Text("全部启动")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(theme.blue, in: .rect(cornerRadius: 7))
                }
                .buttonStyle(Press(scale: 0.97))

                Button { store.stopAll() } label: {
                    Text("全部停止")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(theme.fill2, in: .rect(cornerRadius: 7))
                }
                .buttonStyle(Press(scale: 0.97))
            }
        }
        .padding(.top, 7)
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
}
