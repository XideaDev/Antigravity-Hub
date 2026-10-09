import AppKit
import SwiftUI

/// Which page the popover is showing.
///
/// Antigravity Hub navigates *inside* the popover instead of presenting sheets: a
/// `MenuBarExtra` panel is a transient window, and a modal sheet on top of it
/// is a good way to have the whole panel dismissed out from under the user.
enum PanelRoute: Equatable {
    case list
    case create
    case edit(String)
    case logs(String)
    case settings
    case about
}

/// Navigation state for the popover, lifted out of the view so the AppKit shell
/// can deep-link into it — right-click → 设置… has to open the panel already
/// showing the settings page, not the profile list.
final class PanelRouter: ObservableObject {
    static let shared = PanelRouter()
    @Published var route: PanelRoute = .list
    private init() {}
}

extension Notification.Name {
    /// Posted when the panel itself should close (Esc on the list page).
    static let ghubClosePanel = Notification.Name("dev.ghub.closePanel")
}

/// Fixed panel geometry.
///
/// Every page renders at the same size on purpose: an auto-sizing panel visibly
/// jumps as you move between the list, settings and about pages, and that reads
/// as the window flickering. A single fixed height trades a little empty space
/// on short pages for a panel that never moves.
///
/// 460 is the smallest value that fits the tallest page (设置) with real margin.
/// The earlier 420 was derived from estimates that turned out to be ~40pt too
/// optimistic, and the overflow escaped the rounded corners — which is why the
/// settings and create pages showed square bottom corners.
enum PanelMetrics {
    static let width: CGFloat = 348
    static let height: CGFloat = 460
    static let cornerRadius: CGFloat = 12
}

/// The panel's frosted background lives in the AppKit layer (see `setUpPanel`)
/// rather than here: `NSVisualEffectView` has to be the window's content view to
/// composite the way `NSPopover` does, and it can't be reached through a SwiftUI
/// `.background` modifier.

// MARK: - Shared control chrome

/// Comfortable text button. macOS controls want ~22–28pt of height and 12–13px
/// type; the earlier 11px/18pt pills read as "everything is tiny".
struct SoftButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = .secondary
    var prominent = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .medium))
                }
                Text(title).font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.accentColor : tint)
        .onHover { hovering = $0 }
    }

    private var fill: Color {
        if hovering { return Color.primary.opacity(0.12) }
        return prominent ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06)
    }
}

/// Icon-only toolbar chip for the expanded profile drawer.
///
/// The label is dropped on purpose. Five labelled chips across a 348pt panel
/// leave each roughly 60pt wide, which truncates *every one* of them to an
/// ellipsis — the row ends up reading as five identical grey pills. An SF Symbol
/// plus a tooltip is what macOS toolbars have always done, and it buys enough
/// width back that the destructive action can sit apart from the rest.
struct IconChip: View {
    let systemImage: String
    let help: String
    var tint: Color?
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? Color.primary.opacity(0.11) : Color.primary.opacity(0.05))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? Color.secondary)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Header glyph button: a 28×28pt hit target, which is the whole point —
/// the previous 11px glyphs had no clickable area and looked like decoration.
struct HeaderIconButton: View {
    let systemImage: String
    let help: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            glyph
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .onHover { hovering = $0 }
    }

    private var glyph: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(hovering ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Root panel

struct ConsolePanel: View {
    @EnvironmentObject private var store: ProfileStore
    @ObservedObject private var router = PanelRouter.shared
    @ObservedObject private var loc = LocalizationManager.shared

    /// Accordion: at most one profile shows its detail drawer, which keeps the
    /// panel from growing taller than the screen when several are expanded.
    @State private var expandedName: String?
    /// Drives the keyboard selection ring.
    @State private var selectedName: String?
    /// Detail fetched on demand, since it is the only snapshot that reports
    /// on-disk size (it walks the whole sandbox, so never poll it).
    @State private var details: [String: ProfileSnapshot] = [:]
    @FocusState private var listFocused: Bool

    private var running: [ProfileSnapshot] { store.profiles.filter(\.isRunning) }
    private var stopped: [ProfileSnapshot] { store.profiles.filter { !$0.isRunning } }
    private var ordered: [ProfileSnapshot] { running + stopped }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if store.errorMessage != nil || store.notice != nil {
                Divider()
                statusBar
            }
            Divider()
            footer
        }
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        // The panel's window supplies the material (an NSVisualEffectView used as
        // the window's content view, the way NSPopover does it); the content only
        // has to stay transparent and respect the same rounded shape.
        .clipShape(
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
        )
        .onAppear { store.refresh() }
        // Esc unwinds one level at a time: sub-page → list, then expanded row →
        // collapsed, then close the panel.
        .onKeyPress(.escape) {
            if router.route != .list {
                goBack()
            } else if expandedName != nil || selectedName != nil {
                expandedName = nil
                selectedName = nil
            } else {
                NotificationCenter.default.post(name: .ghubClosePanel, object: nil)
            }
            return .handled
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        switch router.route {
        case .list: listHeader
        case .create: subHeader(title: "new_profile".localized)
        case let .edit(name): subHeader(title: "edit_title".localized(with: name))
        case let .logs(name): subHeader(title: "logs_title".localized(with: name))
        case .settings: subHeader(title: "settings".localized)
        case .about: subHeader(title: "about_app".localized)
        }
    }

    private var headerAppIcon: some View {
        Group {
            if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap({ NSImage(contentsOf: $0) }) ?? NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 17, height: 17)
            } else {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var listHeader: some View {
        HStack(spacing: 4) {
            headerAppIcon

            Text("Antigravity Hub")
                .font(.system(size: 14, weight: .semibold))
                .padding(.leading, 2)

            if !store.profiles.isEmpty {
                Text("running_count".localized(with: store.runningCount, store.totalCount))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
            }

            Spacer(minLength: 6)

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 14)
            }

            HeaderIconButton(systemImage: "plus", help: "\("new_profile".localized) (⌘N)") { router.route = .create }
                .keyboardShortcut("n", modifiers: .command)

            HeaderIconButton(systemImage: "arrow.clockwise", help: "\("refresh".localized) (⌘R)") { store.refresh() }
                .keyboardShortcut("r", modifiers: .command)

            HeaderIconButton(systemImage: "gearshape", help: "\("settings".localized) (⌘,)") { router.route = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }
        // Roomy vertically on purpose: the 28pt icon buttons plus the panel's
        // 12pt corner radius left the wordmark looking wedged against the top
        // edge at the previous 6pt.
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func subHeader(title: String) -> some View {
        HStack(spacing: 6) {
            HeaderIconButton(systemImage: "chevron.left", help: "back".localized) { goBack() }

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    /// 关于 returns to 设置, everything else returns to the profile list.
    private func goBack() {
        switch router.route {
        case .about: router.route = .settings
        default: router.route = .list
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch router.route {
        case .list:
            listContent
        case .create:
            CreateProfileView { if $0 { router.route = .list } }
        case let .edit(name):
            editContent(for: name)
        case let .logs(name):
            LogView(profileName: name)
        case .settings:
            SettingsPane { router.route = .about }
        case .about:
            AboutPane()
        }
    }

    @ViewBuilder
    private func editContent(for name: String) -> some View {
        if let snapshot = store.profiles.first(where: { $0.name == name }) {
            EditProfileView(profile: snapshot) { saved in
                if saved { router.route = .list }
            }
        } else {
            Text("profile_not_found".localized)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if store.antigravityMissing {
            antigravityMissingState
        } else if store.profiles.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !running.isEmpty {
                    groupHeader("running_group".localized(with: running.count))
                    ForEach(running) { row(for: $0) }
                }
                if !stopped.isEmpty {
                    groupHeader("stopped_group".localized(with: stopped.count))
                    ForEach(stopped) { row(for: $0) }
                }
            }
            .padding(.bottom, 6)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear { listFocused = true }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.return) { activateSelection(); return .handled }
    }

    private func groupHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 4)
    }

    private func row(for profile: ProfileSnapshot) -> some View {
        ProfileRow(
            profile: profile,
            detail: details[profile.name],
            isExpanded: expandedName == profile.name,
            isSelected: selectedName == profile.name,
            onToggleExpand: { toggleExpanded(profile) },
            onShowLogs: { router.route = .logs(profile.name) },
            onEdit: { router.route = .edit(profile.name) }
        )
    }

    /// The accent ring is reserved for keyboard navigation. A mouse click just
    /// expands the row, so the panel doesn't keep a focus ring around whatever
    /// was last clicked.
    private func toggleExpanded(_ profile: ProfileSnapshot) {
        selectedName = nil
        guard expandedName != profile.name else {
            expandedName = nil
            return
        }
        expandedName = profile.name
        Task {
            guard let detail = await store.details(of: profile.name) else { return }
            await MainActor.run { details[profile.name] = detail }
        }
    }

    private var antigravityMissingState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text("antigravity_missing_title".localized)
                .font(.system(size: 13, weight: .medium))
            Text("antigravity_missing_desc".localized)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SoftButton(title: "open_download_page".localized, systemImage: "arrow.up.right") {
                NSWorkspace.shared.open(URL(string: "https://antigravity.google")!)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("no_profiles_yet".localized)
                .font(.system(size: 13, weight: .medium))
            SoftButton(title: "create_first_profile".localized, systemImage: "plus", prominent: true) {
                router.route = .create
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: Status + footer

    private var statusBar: some View {
        Group {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .onTapGesture { store.dismissError() }
            } else if let notice = store.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.system(size: 12))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            SoftButton(title: "overview".localized, systemImage: "square.grid.2x2") { openOverview() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Spacer(minLength: 4)
            SoftButton(title: "tile_windows".localized, systemImage: "rectangle.split.2x1") { store.tileWindows() }
                .disabled(store.isTiling)
            SoftButton(title: "quit".localized, systemImage: "power") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: Keyboard

    private func moveSelection(_ delta: Int) {
        let items = ordered
        guard !items.isEmpty else { return }
        guard let current = selectedName,
              let index = items.firstIndex(where: { $0.name == current }) else {
            selectedName = delta > 0 ? items.first?.name : items.last?.name
            return
        }
        let next = (index + delta + items.count) % items.count
        selectedName = items[next].name
    }

    private func activateSelection() {
        guard let name = selectedName,
              let profile = ordered.first(where: { $0.name == name }) else { return }
        if profile.isRunning { store.stop(profile) } else { store.launch(profile) }
    }

    // MARK: Actions

    /// Hands off to the overview window and dismisses the panel — leaving both
    /// surfaces open at once would just be two lists of the same thing.
    private func openOverview() {
        NotificationCenter.default.post(name: .ghubClosePanel, object: nil)
        OverviewWindowController.shared.show(store: store)
    }
}

// MARK: - Profile row

struct ProfileRow: View {
    @EnvironmentObject private var store: ProfileStore
    @ObservedObject private var loc = LocalizationManager.shared
    let profile: ProfileSnapshot
    /// Fetched lazily on expand — carries the on-disk size the poll loop can't.
    let detail: ProfileSnapshot?
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpand: () -> Void
    let onShowLogs: () -> Void
    let onEdit: () -> Void

    @State private var confirmingDelete = false
    @State private var hovering = false
    @AppStorage(PrefKey.maskAccounts) private var maskAccounts: Bool = false

    private var isBusy: Bool { store.busy.contains(profile.name) }

    var body: some View {
        VStack(spacing: 0) {
            compactLine
            if isExpanded { drawer }
        }
        .padding(.horizontal, 6)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
        .onHover { hovering = $0 }
    }

    /// Expanded reads as a raised card; keyboard selection is a separate accent
    /// ring. Conflating the two (a blue wash on tap) made a single click look
    /// like a heavyweight selection.
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.accentColor.opacity(isSelected ? 0.5 : 0), lineWidth: 1.5)
            )
            .padding(.horizontal, 5)
    }

    private var fill: Color {
        if isExpanded { return Color.primary.opacity(0.055) }
        if hovering { return Color.primary.opacity(0.035) }
        return .clear
    }

    // MARK: Collapsed line

    private var compactLine: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(profile.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)

            Text(profile.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)

            Text(profile.maskedAccount(enabled: maskAccounts))
                .font(.system(size: 12))
                .foregroundStyle(profile.hasAccount ? Color.secondary : Color.orange)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            primaryButton
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .contextMenu {
            Button {
                ProfileEngine.openTerminal(with: profile.cliCommand)
            } label: {
                Label("open_cli_in_terminal".localized, systemImage: "terminal")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(profile.cliCommand, forType: .string)
                store.showNotice("cli_cmd_copied".localized)
            } label: {
                Label("copy_cli_cmd".localized, systemImage: "doc.on.doc")
            }

            if ProfileEngine.aionUiDatabaseURL != nil {
                Button {
                    if let target = ProfileEngine.profile(named: profile.name) {
                        ProfileEngine.syncToAionUi(for: target)
                        store.showNotice("synced_to_aionui".localized)
                    }
                } label: {
                    Label("sync_to_aionui".localized, systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Divider()

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: profile.directory.path)
            } label: {
                Label("open_in_finder".localized, systemImage: "folder")
            }
        }
    }

    private var primaryButton: some View {
        SoftButton(
            title: profile.isRunning ? "stop".localized : "launch".localized,
            systemImage: profile.isRunning ? "stop.fill" : "play.fill",
            prominent: !profile.isRunning
        ) {
            if profile.isRunning { store.stop(profile) } else { store.launch(profile) }
        }
        .disabled(isBusy || store.isBatching)
        .overlay(alignment: .leading) {
            if isBusy {
                ProgressView().controlSize(.mini).scaleEffect(0.5).offset(x: 6)
            }
        }
    }

    // MARK: Drawer

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 9) {
            if confirmingDelete {
                HStack(spacing: 8) {
                    Text("confirm_delete".localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                    Spacer(minLength: 4)
                    SoftButton(title: "cancel".localized) { confirmingDelete = false }
                    SoftButton(title: "delete".localized, tint: .red, prominent: true) {
                        confirmingDelete = false
                        store.delete(profile)
                    }
                }
            } else {
                Text(metaLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    IconChip(systemImage: "terminal", help: "open_cli_in_terminal".localized) {
                        ProfileEngine.openTerminal(with: profile.cliCommand)
                    }
                    IconChip(systemImage: "doc.text", help: "view_logs".localized, action: onShowLogs)
                    IconChip(systemImage: "folder", help: "reveal_in_finder".localized) {
                        NSWorkspace.shared.selectFile(
                            nil,
                            inFileViewerRootedAtPath: profile.directory.path
                        )
                    }
                    if profile.hasAccount {
                        IconChip(systemImage: "doc.on.doc", help: "copy_account_format".localized(with: profile.displayAccount)) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(profile.displayAccount, forType: .string)
                            store.showNotice("account_copied".localized)
                        }
                    }
                    IconChip(systemImage: "pencil", help: "edit_profile".localized, action: onEdit)

                    Spacer(minLength: 4)

                    IconChip(systemImage: "trash", help: "delete_profile".localized, tint: .red) {
                        confirmingDelete = true
                    }
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 1)
        .padding(.bottom, 10)
        .padding(.leading, 6)
    }

    private var metaLine: String {
        let source = detail ?? profile
        var parts: [String] = []
        if source.isRunning { parts.append(source.pidLabel) }
        // `size` stays null until the detail fetch lands, and the "—" placeholder
        // read as a rendering glitch when it led the line — omit it entirely.
        if let size = source.size, !size.isEmpty { parts.append(size) }
        if source.inheritedFrom != nil { parts.append("inherited_host_config".localized) }
        if source.isExpired { parts.append("token_expired".localized) }
        else if source.isExpiring { parts.append("token_expiring_soon".localized) }
        if let note = source.note, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? "reading_details".localized : parts.joined(separator: " · ")
    }
}
