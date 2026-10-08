import AppKit
import Security
import SwiftUI

extension Notification.Name {
    /// Posted when a preference that affects the menu bar icon changes, so the
    /// AppKit shell can re-render the status item without a shared store.
    static let ghubMenuBarIconChanged = Notification.Name("dev.ghub.menuBarIconChanged")
}

// MARK: - 设置页（面板内）

/// Settings live *inside* the panel rather than in a separate window.
///
/// A `TabView`-in-a-window would have needed hand-tuned window sizing and
/// toolbar restyling to look native; hosting the same content as one more
/// `PanelRoute` reuses the navigation the panel already has, keeps the window
/// chrome out of the picture entirely, and puts settings one right-click away
/// from the menu bar icon.
struct SettingsPane: View {
    @EnvironmentObject private var store: ProfileStore
    let onOpenAbout: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @State private var cadence = RefreshCadence.current
    @State private var iconID = MenuBarGlyph.selected.id

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                generalSection
                iconSection
                utilityRow
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: 通用

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("通用")

            card {
                Toggle("开机自启", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 13))
                    .onChange(of: launchAtLogin) { _, newValue in
                        applyLaunchAtLogin(newValue)
                    }
            }
            hint(
                loginError ?? LaunchAtLogin.statusDescription,
                tint: loginError == nil ? Color.secondary.opacity(0.55) : .orange
            )

            card {
                Text("刷新频率").font(.system(size: 13))
                Spacer(minLength: 6)
                Picker("", selection: $cadence) {
                    ForEach(RefreshCadence.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 116)
                .onChange(of: cadence) { _, newValue in
                    RefreshCadence.select(newValue)
                    store.restartPolling()
                }
            }
            hint(cadence.detail)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            // Registration is refused outright when the bundle isn't in an
            // Applications folder or isn't signed — surface it instead of
            // leaving the toggle lying about the real state.
            loginError = "设置失败：\(error.localizedDescription)"
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    // MARK: 菜单栏图标

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("菜单栏图标")

            LazyVGrid(columns: iconColumns, spacing: 6) {
                ForEach(MenuBarGlyph.catalog) { glyph in
                    iconTile(glyph)
                }
            }
            .padding(.horizontal, 10)

            hint("实心 = 有分身运行中")
        }
    }

    private func iconTile(_ glyph: MenuBarGlyph) -> some View {
        let isSelected = glyph.id == iconID
        return Button {
            MenuBarGlyph.select(glyph)
            iconID = glyph.id
            NotificationCenter.default.post(name: .ghubMenuBarIconChanged, object: nil)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: glyph.symbol(active: store.runningCount > 0))
                    .font(.system(size: 15))
                    .frame(height: 18)
                Text(glyph.label)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.accentColor.opacity(isSelected ? 0.65 : 0), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(glyph.label)
    }

    // MARK: 底部工具行

    /// 关于 and 恢复默认 share one row: they're both one-off utility actions, and
    /// a second stacked row pushed the page past the panel's fixed height.
    private var utilityRow: some View {
        HStack(spacing: 6) {
            SoftButton(title: "关于 Antigravity Hub", systemImage: "info.circle", action: onOpenAbout)
            Spacer(minLength: 4)
            SoftButton(title: "恢复默认", systemImage: "arrow.counterclockwise") { restoreDefaults() }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
    }

    private func restoreDefaults() {
        MenuBarGlyph.select(.fallback)
        iconID = MenuBarGlyph.fallback.id
        NotificationCenter.default.post(name: .ghubMenuBarIconChanged, object: nil)

        RefreshCadence.select(.normal)
        cadence = .normal
        store.restartPolling()
    }

    // MARK: 小组件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 10)
    }

    private func hint(_ text: String, tint: Color = Color.secondary.opacity(0.55)) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.top, 5)
            .padding(.bottom, 8)
    }
}

// MARK: - 关于页（面板内）

struct AboutPane: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var signingInfo: (title: String, isDeveloperID: Bool, isSigned: Bool) {
        guard let url = Bundle.main.executableURL as CFURL? else {
            return ("未知状态", false, false)
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return ("未签名（开发副本）", false, false)
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let info else {
            return ("未签名（开发副本）", false, false)
        }
        let dict = info as NSDictionary
        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return ("Developer ID 公证 · 团队 \(team)", true, true)
        }
        if let authority = dict["authority"] as? String, !authority.isEmpty {
            let isDevID = authority.contains("Developer ID")
            return (authority, isDevID, true)
        }
        if dict[kSecCodeInfoIdentifier as String] != nil {
            return ("Ad-hoc 本地开发签名", false, true)
        }
        return ("未签名（开发副本）", false, false)
    }

    private var archName: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Universal"
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().padding(.horizontal, 10)
                infoRows
                Divider().padding(.horizontal, 10)
                highlights
                Divider().padding(.horizontal, 10)
                licenses
                Spacer(minLength: 8)
                links
            }
            .padding(.bottom, 12)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AppIconBadge()
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Antigravity Hub")
                        .font(.system(size: 15, weight: .semibold))
                    Text("v\(appVersion)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .foregroundStyle(Color.accentColor)
                }
                Text("构建 \(buildNumber) · macOS 14+")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Google Antigravity 原生多分身管理器")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private struct AppIconBadge: View {
        private var iconImage: NSImage? {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let img = NSImage(contentsOf: url), img.isValid {
                return img
            }
            let sys = NSImage(named: NSImage.applicationIconName)
            if let sys, sys.isValid { return sys }
            return nil
        }

        var body: some View {
            if let iconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.15, green: 0.55, blue: 0.95),
                                     Color(red: 0.98, green: 0.50, blue: 0.20)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    Image(systemName: "circle.circle.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            }
        }
    }

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 7) {
            infoRowWithAction("Antigravity 路径", ProfileEngine.antigravityAppURL?.path ?? "未找到") {
                if let url = ProfileEngine.antigravityAppURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            infoRowWithAction("分身数据目录", ProfileEngine.root.path) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ProfileEngine.root.path)
            }
            signingRow
            infoRow("系统架构", "\(archName) · \(ProcessInfo.processInfo.operatingSystemVersionString)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var signingRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("签名状态")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            HStack(spacing: 5) {
                Circle()
                    .fill(signingInfo.isDeveloperID ? Color.green : (signingInfo.isSigned ? Color.blue : Color.orange))
                    .frame(width: 6, height: 6)
                Text(signingInfo.title)
                    .font(.system(size: 11))
                    .foregroundStyle(signingInfo.isDeveloperID ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("核心机制")
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 10)

            highlightItem(icon: "shield.lefthalf.filled", title: "物理沙箱隔离", desc: "基于 Chromium 官方 --user-data-dir 与独立 HOME，每个分身数据与配置物理隔离。")
            highlightItem(icon: "person.badge.key.fill", title: "多账号互不干扰", desc: "各实例独立持有独立的 Google 账号与 Gemini 配额，告别反复登出与切换。")
            highlightItem(icon: "bolt.badge.checkmark.fill", title: "零补丁 · 零依赖", desc: "不修改 Antigravity 二进制与数据库，纯 Swift 原生构建，无外部依赖。")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func highlightItem(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
                .frame(width: 14, height: 14)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(desc)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 1)
    }

    private var licenses: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开源许可与商标声明")
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 10)

            license(
                "Antigravity Hub — MIT License",
                "本项目的全部代码为独立实现，未包含任何第三方管理工具的源代码。"
            )
            license(
                "商标声明",
                "Google、Antigravity、Gemini 为 Google LLC 商标。本项目为非官方独立工具，与 Google LLC 无隶属关系。"
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var links: some View {
        HStack(spacing: 6) {
            SoftButton(title: "更新日志", systemImage: "list.bullet.rectangle") {
                NSWorkspace.shared.open(URL(string: "https://github.com/XideaDev/Antigravity-Hub/releases")!)
            }
            SoftButton(title: "GitHub 仓库", systemImage: "arrow.up.right") {
                NSWorkspace.shared.open(URL(string: "https://github.com/XideaDev/Antigravity-Hub")!)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func infoRowWithAction(_ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button(action: action) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("在 Finder 中显示")
        }
    }

    private func license(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
