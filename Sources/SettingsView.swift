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
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var updater = UpdaterManager.shared
    let onOpenAbout: () -> Void

    @AppStorage(PrefKey.maskAccounts) private var maskAccounts: Bool = false
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
            sectionTitle("general".localized)

            card {
                Toggle("launch_at_login".localized, isOn: $launchAtLogin)
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
                Toggle("account_masking".localized, isOn: $maskAccounts)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 13))
            }
            hint("account_masking_hint".localized)

            card {
                Text("language".localized).font(.system(size: 13))
                Spacer(minLength: 6)
                Picker("", selection: $loc.currentLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 116)
            }
            hint("")

            card {
                Toggle("auto_check_updates".localized, isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))
            }
            hint("auto_check_updates_hint".localized)

            card {
                Text("check_for_updates".localized).font(.system(size: 13))
                Spacer(minLength: 6)
                Button(action: { updater.checkForUpdates() }) {
                    Text("check_updates_now".localized)
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!updater.canCheckForUpdates)
            }
            hint("")

            card {
                Text("refresh_interval".localized).font(.system(size: 13))
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
            loginError = "set_failed".localized(with: error.localizedDescription)
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    // MARK: 菜单栏图标

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("menubar_icon".localized)

            LazyVGrid(columns: iconColumns, spacing: 6) {
                ForEach(MenuBarGlyph.catalog) { glyph in
                    iconTile(glyph)
                }
            }
            .padding(.horizontal, 10)

            hint("menubar_icon_hint".localized)
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
            SoftButton(title: "about_app".localized, systemImage: "info.circle", action: onOpenAbout)
            Spacer(minLength: 4)
            SoftButton(title: "restore_defaults".localized, systemImage: "arrow.counterclockwise") { restoreDefaults() }
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
        Group {
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer(minLength: 6)
            } else {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
        }
    }
}

// MARK: - 关于页（面板内）

struct AboutPane: View {
    @ObservedObject private var loc = LocalizationManager.shared

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var signingInfo: (title: String, isDeveloperID: Bool, isSigned: Bool) {
        guard let url = Bundle.main.executableURL as CFURL? else {
            return ("signing_unknown".localized, false, false)
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return ("signing_unsigned".localized, false, false)
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let info else {
            return ("signing_unsigned".localized, false, false)
        }
        let dict = info as NSDictionary
        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return ("signing_dev_id".localized(with: team), true, true)
        }
        if let authority = dict["authority"] as? String, !authority.isEmpty {
            let isDevID = authority.contains("Developer ID")
            return (authority, isDevID, true)
        }
        if dict[kSecCodeInfoIdentifier as String] != nil {
            return ("signing_adhoc".localized, false, true)
        }
        return ("signing_unsigned".localized, false, false)
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
                Text("build_label".localized(with: buildNumber))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("app_role_desc".localized)
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
            infoRowWithAction("antigravity_path".localized, ProfileEngine.antigravityAppURL?.path ?? "not_found".localized) {
                if let url = ProfileEngine.antigravityAppURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            infoRowWithAction("profiles_data_dir".localized, ProfileEngine.root.path) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ProfileEngine.root.path)
            }
            signingRow
            infoRow("system_arch".localized, "\(archName) · \(ProcessInfo.processInfo.operatingSystemVersionString)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var signingRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("signing_status".localized)
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
            Text("core_mechanisms".localized)
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 10)

            highlightItem(icon: "shield.lefthalf.filled", title: "sandbox_isolation_title".localized, desc: "sandbox_isolation_desc".localized)
            highlightItem(icon: "person.badge.key.fill", title: "multi_account_title".localized, desc: "multi_account_desc".localized)
            highlightItem(icon: "bolt.badge.checkmark.fill", title: "zero_patch_title".localized, desc: "zero_patch_desc".localized)
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
            Text("license_and_trademark".localized)
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 10)

            license(
                "Antigravity Hub — MIT License",
                "license_desc".localized
            )
            license(
                "trademark_notice".localized,
                "trademark_desc".localized
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var links: some View {
        HStack(spacing: 6) {
            SoftButton(title: "changelog".localized, systemImage: "list.bullet.rectangle") {
                NSWorkspace.shared.open(URL(string: "https://github.com/XideaDev/Antigravity-Hub/releases")!)
            }
            SoftButton(title: "github_repo".localized, systemImage: "arrow.up.right") {
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
            .help("reveal_in_finder".localized)
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
