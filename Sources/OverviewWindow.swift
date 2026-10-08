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
    @AppStorage(PrefKey.maskAccounts) private var maskAccounts: Bool = false

    @State private var query = ""
    @State private var drawer: DrawerRoute?

    enum DrawerRoute: Equatable {
        case detail(String)  // profile name
        case create
        case edit(String)    // profile name
    }

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 12)]

    private var filtered: [ProfileSnapshot] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return store.profiles }
        return store.profiles.filter {
            $0.name.lowercased().contains(needle)
                || $0.displayAccount.lowercased().contains(needle)
                || ($0.note?.lowercased().contains(needle) ?? false)
        }
    }

    private var running: [ProfileSnapshot] { filtered.filter(\.isRunning) }
    private var stopped: [ProfileSnapshot] { filtered.filter { !$0.isRunning } }

    private var selectedProfileName: String? {
        switch drawer {
        case let .detail(name), let .edit(name): return name
        case .create, .none: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                gridArea
                if let drawer {
                    Divider()
                    drawerContent(for: drawer)
                        .frame(width: 310)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeOut(duration: 0.16), value: drawer)
        .onExitCommand {
            if drawer != nil {
                withAnimation(.easeOut(duration: 0.16)) { drawer = nil }
            } else {
                OverviewWindowController.shared.close()
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Leaves room for the traffic lights, which float over this row
            // because the title bar is transparent.
            Spacer().frame(width: 62)

            // App Brand Logo & Name (Requirement 1, Callout ❶)
            HStack(spacing: 7) {
                if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap({ NSImage(contentsOf: $0) }) ?? NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 19, height: 19)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                }
                Text("Antigravity Hub")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.trailing, 2)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("搜索分身或账号", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 156)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            Text(store.statusSummary)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            privacyToggle

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            SoftButton(title: "全部启动", systemImage: "play.fill") { store.launchAll() }
                .disabled(store.isBatching || store.runningCount == store.totalCount)
            SoftButton(title: "全部停止", systemImage: "stop.fill") { store.stopAll() }
                .disabled(store.isBatching || store.runningCount == 0)
            SoftButton(title: "平铺窗口", systemImage: "rectangle.split.2x1") { store.tileWindows() }
                .disabled(store.isTiling)
            SoftButton(title: "新建", systemImage: "plus", prominent: true) {
                withAnimation(.easeOut(duration: 0.16)) {
                    drawer = (drawer == .create) ? nil : .create
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 9)
    }

    private var privacyToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                maskAccounts.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: maskAccounts ? "eye.slash.fill" : "eye")
                    .font(.system(size: 11, weight: .medium))
                Text(maskAccounts ? "已脱敏" : "脱敏")
                    .font(.system(size: 11))
            }
            .foregroundStyle(maskAccounts ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(maskAccounts ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .help(maskAccounts ? "当前已开启账号脱敏保护，点击显示完整邮箱" : "点击开启账号隐私打码 (隐藏敏感部分)")
    }

    // MARK: Grid

    private var gridArea: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: max(240, proxy.size.height - 40))
                    } else {
                        if !running.isEmpty {
                            groupHeader("运行中 · \(running.count)")
                            cardGrid(running, showsNewCard: stopped.isEmpty)
                        }
                        if !stopped.isEmpty {
                            groupHeader("已停止 · \(stopped.count)")
                            cardGrid(stopped, showsNewCard: true)
                        }
                    }
                }
                .padding(.bottom, 24)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if drawer != nil {
                        withAnimation(.easeOut(duration: 0.16)) {
                            drawer = nil
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .contentShape(Rectangle())
                .onTapGesture {
                    if drawer != nil {
                        withAnimation(.easeOut(duration: 0.16)) {
                            drawer = nil
                        }
                    }
                }
        )
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
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(items) { profile in
                ProfileCard(
                    profile: profile,
                    isSelected: selectedProfileName == profile.name,
                    maskAccounts: maskAccounts,
                    onSelect: {
                        withAnimation(.easeOut(duration: 0.16)) {
                            if drawer == .detail(profile.name) {
                                drawer = nil
                            } else {
                                drawer = .detail(profile.name)
                            }
                        }
                    },
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
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                drawer = .create
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                Text("新建分身")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 116)
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
                    withAnimation(.easeOut(duration: 0.16)) {
                        drawer = .create
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    // MARK: Drawer

    @ViewBuilder
    private func drawerContent(for route: DrawerRoute) -> some View {
        switch route {
        case let .detail(name):
            if let profile = store.profiles.first(where: { $0.name == name }) {
                ProfileDetailPane(
                    profile: profile,
                    maskAccounts: maskAccounts,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.16)) { drawer = nil }
                    },
                    onEdit: {
                        withAnimation(.easeOut(duration: 0.16)) { drawer = .edit(name) }
                    }
                )
            } else {
                drawerEmptyOrGone
            }

        case .create:
            VStack(spacing: 0) {
                drawerHeader(title: "新建分身", icon: "plus.circle.fill") {
                    withAnimation(.easeOut(duration: 0.16)) { drawer = nil }
                }
                Divider()
                CreateProfileView { created in
                    withAnimation(.easeOut(duration: 0.16)) {
                        drawer = nil
                    }
                }
                .environmentObject(store)
            }

        case let .edit(name):
            if let profile = store.profiles.first(where: { $0.name == name }) {
                VStack(spacing: 0) {
                    drawerHeader(title: "编辑 · \(profile.name)", icon: "pencil.circle.fill") {
                        withAnimation(.easeOut(duration: 0.16)) { drawer = .detail(name) }
                    }
                    Divider()
                    EditProfileView(profile: profile) { saved in
                        withAnimation(.easeOut(duration: 0.16)) {
                            drawer = saved ? nil : .detail(name)
                        }
                    }
                    .environmentObject(store)
                }
            } else {
                drawerEmptyOrGone
            }
        }
    }

    private func drawerHeader(title: String, icon: String, onClose: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭面板 (ESC)")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var drawerEmptyOrGone: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("该分身已不存在")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            SoftButton(title: "关闭") {
                withAnimation(.easeOut(duration: 0.16)) { drawer = nil }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card

struct ProfileCard: View {
    @EnvironmentObject private var store: ProfileStore
    let profile: ProfileSnapshot
    let isSelected: Bool
    let maskAccounts: Bool
    let onSelect: () -> Void
    let onToggleRun: () -> Void

    @State private var hovering = false

    private var isBusy: Bool { store.busy.contains(profile.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Circle()
                    .fill(profile.isRunning ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(profile.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if profile.isRunning {
                    Text("PID \(profile.pid ?? 0)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            Text(profile.maskedAccount(enabled: maskAccounts))
                .font(.system(size: 11))
                .foregroundStyle(profile.hasAccount ? Color.secondary : Color.orange)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(profile.displayAccount)

            cardSubInfo

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
                      : Color.primary.opacity(hovering ? 0.07 : 0.04))
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

    @ViewBuilder
    private var cardSubInfo: some View {
        if let note = profile.note, !note.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 9))
                Text(note)
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        } else if let source = profile.inheritedFrom, !source.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9))
                Text(source == "host" ? "继承宿主配置" : "自 \(source)")
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        } else if let size = profile.size, !size.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 9))
                Text(size)
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "cube")
                    .font(.system(size: 9))
                Text("独立沙箱")
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Detail pane

struct ProfileDetailPane: View {
    @EnvironmentObject private var store: ProfileStore
    let profile: ProfileSnapshot
    let maskAccounts: Bool
    let onClose: () -> Void
    let onEdit: () -> Void

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
            Button("永久删除", role: .destructive) {
                store.delete(profile)
                onClose()
            }
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
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("编辑名字、描述与链接策略")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("收起详情 (ESC)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            row("账号", shown.maskedAccount(enabled: maskAccounts), tint: shown.hasAccount ? nil : .orange)
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
                    NSPasteboard.general.setString(profile.account?.email ?? profile.displayAccount, forType: .string)
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
