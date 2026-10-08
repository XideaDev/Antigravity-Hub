import AppKit
import SwiftUI

// MARK: - Window

/// Owns the single overview window.
///
/// A real `NSWindow` rather than another popover: the point of this surface is
/// to spread out on a large display, which a 348pt transient panel cannot do.
/// It shares `ProfileStore` with the panel, so it is a second *view* of the same
/// state rather than a second application.
final class OverviewWindowController {
    static let shared = OverviewWindowController()

    private var window: NSWindow?

    private init() {}

    var isVisible: Bool { window?.isVisible ?? false }

    func show(store: ProfileStore) {
        if window == nil { build(store) }
        guard let window else { return }

        // Order the window on screen *before* asking to activate: an accessory
        // app with no window that can become main has nothing to activate, and
        // macOS refuses. With the window present, activation takes.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        retryMakeKey(attempt: 0)
    }

    func close() {
        window?.orderOut(nil)
    }

    /// Same reasoning as the menu bar panel: the window has only just appeared,
    /// so the first `makeKey()` can be a no-op. Retry briefly rather than leave
    /// the window on screen but unable to receive the keyboard.
    private func retryMakeKey(attempt: Int) {
        guard let window, window.isVisible else { return }
        if window.isKeyWindow { return }
        guard attempt < 12 else { return }
        window.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.retryMakeKey(attempt: attempt + 1)
        }
    }

    private func build(_ store: ProfileStore) {
        // `PanelHostingView` also accepts a first click while the window is
        // still becoming key, so the very first interaction isn't swallowed.
        let hosting = PanelHostingView(rootView: AnyView(OverviewView().environmentObject(store)))
        hosting.sizingOptions = []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Antigravity Hub"
        // Merge the toolbar into the title bar area so the window reads as one
        // surface instead of a title bar stacked on top of another bar.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 460)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AntigravityHubOverview")
        window.contentView = hosting
        window.center()
        self.window = window
    }
}

// MARK: - Root view

struct OverviewView: View {
    @EnvironmentObject private var store: ProfileStore

    @State private var query = ""
    @State private var selected: String?
    @State private var isCreating = false

    private let columns = [GridItem(.adaptive(minimum: 196, maximum: 280), spacing: 10)]

    private var filtered: [ProfileSnapshot] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return store.profiles }
        return store.profiles.filter {
            $0.name.lowercased().contains(needle)
                || $0.displayAccount.lowercased().contains(needle)
        }
    }

    private var running: [ProfileSnapshot] { filtered.filter(\.isRunning) }
    private var stopped: [ProfileSnapshot] { filtered.filter { !$0.isRunning } }

    private var selectedProfile: ProfileSnapshot? {
        guard let selected else { return nil }
        return store.profiles.first { $0.name == selected }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                gridArea
                if let profile = selectedProfile {
                    Divider()
                    ProfileDetailPane(profile: profile, onClose: { selected = nil })
                        .frame(width: 268)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeOut(duration: 0.16), value: selected)
        .sheet(isPresented: $isCreating) {
            CreateProfileView { created in
                isCreating = false
                if created { selected = nil }
            }
            .environmentObject(store)
            .frame(width: 400, height: 540)
        }
        .onExitCommand { OverviewWindowController.shared.close() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Leaves room for the traffic lights, which float over this row
            // because the title bar is transparent.
            Spacer().frame(width: 62)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("搜索分身或账号", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 168)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            Text(store.statusSummary)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            SoftButton(title: "全部启动", systemImage: "play.fill") { store.launchAll() }
                .disabled(store.isBatching || store.runningCount == store.totalCount)
            SoftButton(title: "全部停止", systemImage: "stop.fill") { store.stopAll() }
                .disabled(store.isBatching || store.runningCount == 0)
            SoftButton(title: "平铺窗口", systemImage: "rectangle.split.2x1") { store.tileWindows() }
                .disabled(store.isTiling)
            SoftButton(title: "新建", systemImage: "plus", prominent: true) { isCreating = true }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 9)
    }

    // MARK: Grid

    private var gridArea: some View {
        ScrollView {
            if filtered.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if !running.isEmpty {
                        groupHeader("运行中 · \(running.count)")
                        cardGrid(running, showsNewCard: stopped.isEmpty)
                    }
                    if !stopped.isEmpty {
                        groupHeader("已停止 · \(stopped.count)")
                        cardGrid(stopped, showsNewCard: true)
                    }
                }
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 7)
    }

    private func cardGrid(_ items: [ProfileSnapshot], showsNewCard: Bool) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(items) { profile in
                ProfileCard(
                    profile: profile,
                    isSelected: selected == profile.name,
                    onSelect: { selected = profile.name },
                    onToggleRun: {
                        if profile.isRunning { store.stop(profile) } else { store.launch(profile) }
                    }
                )
            }
            if showsNewCard { newProfileCard }
        }
        .padding(.horizontal, 16)
    }

    private var newProfileCard: some View {
        Button { isCreating = true } label: {
            VStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                Text("新建分身")
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .foregroundStyle(.tertiary)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        Color.primary.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "还没有分身" : "没有匹配的分身")
                .font(.system(size: 13, weight: .medium))
            if query.isEmpty {
                SoftButton(title: "新建第一个分身", systemImage: "plus", prominent: true) {
                    isCreating = true
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }
}

// MARK: - Card

struct ProfileCard: View {
    @EnvironmentObject private var store: ProfileStore
    let profile: ProfileSnapshot
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleRun: () -> Void

    @State private var hovering = false

    private var isBusy: Bool { store.busy.contains(profile.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Circle()
                    .fill(profile.isRunning ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 9, height: 9)
                Text(profile.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if profile.isRunning {
                    Text("PID \(profile.pid ?? 0)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            Text(profile.displayAccount)
                .font(.system(size: 11))
                .foregroundStyle(profile.hasAccount ? Color.secondary : Color.orange)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(profile.displaySize)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                SoftButton(
                    title: profile.isRunning ? "停止" : "启动",
                    systemImage: profile.isRunning ? "stop.fill" : "play.fill",
                    prominent: !profile.isRunning,
                    action: onToggleRun
                )
                .disabled(isBusy || store.isBatching)
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView().controlSize(.mini).scaleEffect(0.55)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.12)
                      : Color.primary.opacity(hovering ? 0.07 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 0.55 : 0), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .help(profile.note?.isEmpty == false ? profile.note! : profile.name)
    }
}

// MARK: - Detail pane

/// The part the 348pt panel genuinely cannot do: a full-height, readable log
/// tail next to the profile's complete metadata.
struct ProfileDetailPane: View {
    @EnvironmentObject private var store: ProfileStore
    let profile: ProfileSnapshot
    let onClose: () -> Void

    @State private var detail: ProfileSnapshot?
    @State private var log = ""
    @State private var confirmingDelete = false

    private var shown: ProfileSnapshot { detail ?? profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 12)
            metadata
            Divider().padding(.horizontal, 12)
            logSection
            Spacer(minLength: 0)
            Divider().padding(.horizontal, 12)
            actions
        }
        .background(Color.primary.opacity(0.025))
        .task(id: profile.name) { await reload() }
        .confirmationDialog(
            "确定删除分身「\(profile.name)」？",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) { store.delete(profile) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("该分身的登录状态、聊天记录与本地数据会被一并删除，无法恢复。")
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(profile.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)
            Text(profile.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("收起详情")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            row("账号", shown.displayAccount, tint: shown.hasAccount ? nil : .orange)
            row("状态", shown.isRunning ? "运行中" : "已停止")
            row("体积", shown.displaySize)
            row("目录", shown.directory.path)
            if let note = shown.note, !note.isEmpty {
                row("描述", note)
            }
            if let source = shown.inheritedFrom {
                row("来源", source == "host" ? "继承宿主配置" : source)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func row(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(tint ?? Color.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("日志")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                Text("每 2 秒刷新")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 5)

            ScrollView {
                Text(log.isEmpty ? "暂无日志" : log)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(log.isEmpty ? 0.55 : 1))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            SoftButton(title: "Finder", systemImage: "folder") {
                NSWorkspace.shared.selectFile(
                    nil,
                    inFileViewerRootedAtPath: profile.directory.path
                )
            }
            if profile.hasAccount {
                SoftButton(title: "复制账号", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(profile.displayAccount, forType: .string)
                    store.showNotice("已复制账号")
                }
            }
            Spacer(minLength: 0)
            SoftButton(title: "删除", systemImage: "trash", tint: .red) {
                confirmingDelete = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Pulls the on-disk size and the log tail, then keeps the log fresh while
    /// the pane stays open. The list snapshot deliberately carries no size,
    /// because computing it walks the whole sandbox.
    private func reload() async {
        if let fresh = await store.details(of: profile.name) {
            await MainActor.run { self.detail = fresh }
        }
        while !Task.isCancelled {
            let name = profile.name
            let text = await Task.detached(priority: .utility) { () -> String in
                guard let target = ProfileEngine.profile(named: name) else { return "" }
                return ProfileEngine.logs(of: target, lines: 200)
            }.value
            await MainActor.run { self.log = text }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}
