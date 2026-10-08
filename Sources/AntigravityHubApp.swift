import AppKit
import Combine
import SwiftUI

/// Pure AppKit entry point.
///
/// Antigravity Hub used to be a SwiftUI `MenuBarExtra` app, but that can't tell a left
/// click from a right click on the status item — and the app needs
/// right-click → 设置, the convention for this class of menu bar tool. So the
/// status item, its panel and the settings routing are all built by hand here,
/// with the SwiftUI views hosted via `NSHostingController`.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let store = ProfileStore.shared
    private var statusItem: NSStatusItem!
    private var panel: PanelWindow!
    private var eventMonitor: Any?
    private var iconObserver: AnyCancellable?
    private var routeObserver: AnyCancellable?
    /// Guards `enforcePanelSize` against re-entering through the resize
    /// notification it triggers itself.
    private var isEnforcingSize = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.startPolling()
        setUpStatusItem()
        setUpPanel()

        iconObserver = store.$profiles
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusIcon() }

        NotificationCenter.default.addObserver(
            forName: .ghubMenuBarIconChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatusIcon()
        }

        NotificationCenter.default.addObserver(
            forName: .ghubClosePanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }

        // A page whose SwiftUI content outgrows the frame can quietly resize the
        // window, and the window's shadow then traces square corners below the
        // rounded glass. Re-assert the geometry on every page change, and log it
        // — logging only on show meant the settings page was never observed.
        routeObserver = PanelRouter.shared.$route
            .receive(on: RunLoop.main)
            .sink { [weak self] route in
                guard let self else { return }
                self.enforcePanelSize()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.logLayout(label: "route=\(route)")
                }
            }
    }

    /// Accessory app: closing the panel must not quit Antigravity Hub.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshStatusIcon()
    }

    private func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        let glyph = MenuBarGlyph.selected
        let image = NSImage(
            systemSymbolName: glyph.symbol(active: store.runningCount > 0),
            accessibilityDescription: "Antigravity Hub"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Antigravity Hub · \(store.statusSummary)"
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        Log.write("statusItemClicked secondary=\(isSecondary) type=\(event?.type.rawValue ?? 0)")

        if isSecondary {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    // MARK: - Panel

    private func setUpPanel() {
        let size = NSSize(width: PanelMetrics.width, height: PanelMetrics.height)

        let panel = PanelWindow(
            contentRect: NSRect(origin: .zero, size: size),
            // `.nonactivatingPanel` is load-bearing, not decoration. macOS
            // refuses to activate an accessory app from a status-item click, so
            // `NSApp.activate()` silently does nothing and a plain borderless
            // window can never become key — which swallows the first click on
            // the panel. A nonactivating panel is the one window type that can
            // take key *without* the app being active.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // Background material, newest first.
        //
        // macOS 26 replaced the old `NSVisualEffectView` frosted glass with
        // Liquid Glass, and it is a different API rather than a different
        // material constant — `NSGlassEffectView` is a container that wants its
        // content via `contentView`, and it owns its own corner radius and rim,
        // so none of the mask / layer workarounds below apply to it.
        let hosting = PanelHostingView(rootView: AnyView(ConsolePanel().environmentObject(store)))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.style = .regular
            glass.autoresizingMask = [.width, .height]
            glass.contentView = hosting
            glass.cornerRadius = PanelMetrics.cornerRadius

            // Belt and braces. `cornerRadius` shapes the glass material, but the
            // window's opaque region — and therefore its shadow — still traced a
            // square outline, which reads as square corners. Clipping through a
            // parent layer mask fixes the outline at the source.
            let clip = PanelClipView(frame: NSRect(origin: .zero, size: size))
            clip.autoresizingMask = [.width, .height]
            clip.addSubview(glass)
            panel.contentView = clip
            Log.write("panel background=NSGlassEffectView (Liquid Glass) style=regular "
                + "radius=\(glass.cornerRadius) clipped=\(clip.layer?.masksToBounds == true)")
        } else {
            // Pre-26 fallback: the classic vibrancy view. Its rounded outline
            // has to come from `maskImage` — `wantsLayer` + `layer.cornerRadius`
            // forces offscreen rendering and kills behind-window sampling,
            // leaving a flat grey panel with square corners.
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Self.roundedMask(size: size, radius: PanelMetrics.cornerRadius)
            effect.autoresizingMask = [.width, .height]
            effect.addSubview(hosting)
            panel.contentView = effect
            Log.write("panel background=NSVisualEffectView (legacy) material=\(effect.material.rawValue) "
                + "blending=\(effect.blendingMode.rawValue) mask=\(effect.maskImage != nil)")
        }

        // Re-assert transparency *after* installing the content view, in case
        // AppKit reset it on assignment.
        panel.isOpaque = false
        panel.backgroundColor = .clear

        self.panel = panel

        // The panel must never resize. Watching the window directly catches
        // every cause — page change, row expansion, async content — where
        // hooking only route changes silently missed the row-expansion case.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Log.write("⚠️ panel resized to \(self.panel.frame.size)")
            self.enforcePanelSize()
        }

        Log.write("panel frame=\(panel.frame) opaque=\(panel.isOpaque)")
    }

    /// Binary rounded-rect mask for the effect view. `capInsets` + `.stretch`
    /// keep the corners crisp if the view is ever resized.
    private static func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
            return
        }
        // A plain left-click always lands on the profile list; settings are
        // reached deliberately (gear in the header, or right-click → 设置…).
        PanelRouter.shared.route = .list
        showPanel()
    }

    private func showPanel() {
        let origin = panelOrigin()
        panel.setFrameOrigin(origin)
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: a borderless
        // panel attached to a status item must appear even when the app wasn't
        // the active one, which `makeKeyAndOrderFront` declines to do.
        panel.orderFrontRegardless()
        takeKey()
        installEventMonitor()
        Log.write("showPanel origin=\(origin) visible=\(panel.isVisible)")
        enforcePanelSize()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.logLayout(label: "show")
        }
    }

    /// Force the panel back to its declared geometry, keeping the top edge
    /// pinned so it stays anchored under the status item.
    private func enforcePanelSize() {
        guard panel.isVisible, !isEnforcingSize else { return }
        let target = NSSize(width: PanelMetrics.width, height: PanelMetrics.height)
        var frame = panel.frame
        guard frame.size != target else { return }
        isEnforcingSize = true
        defer { isEnforcingSize = false }
        frame.origin.y += frame.size.height - target.height
        frame.size = target
        panel.setFrame(frame, display: true)
        Log.write("enforcePanelSize corrected to \(target)")
    }

    /// Logs the real geometry of every layer down the view chain, plus how tall
    /// the SwiftUI content actually wants to be. A mismatch at any level is what
    /// lets content escape the rounded corners.
    private func logLayout(label: String) {
        guard panel.isVisible else { return }
        var parts = ["panel=\(panel.frame.size)"]
        var view = panel.contentView
        var depth = 0
        while let current = view, depth < 4 {
            let name = String(describing: type(of: current))
            parts.append("L\(depth)=\(name)\(current.frame.size)")
            if let hosting = current as? NSHostingView<AnyView> {
                parts.append("fitting=\(hosting.fittingSize)")
            }
            view = current.subviews.first
            depth += 1
        }
        Log.write("layout[\(label)] " + parts.joined(separator: " "))
    }

    /// A window can only become key once its app is active, and
    /// `NSApp.activate()` doesn't take effect within the same runloop turn — so
    /// calling `makeKey()` immediately silently fails and the panel ends up
    /// visible but deaf to the keyboard. Poll briefly instead of guessing.
    /// The panel must be key before the user's first click lands, otherwise
    /// AppKit spends that click on focusing the window and the click appears to
    /// do nothing — the "have to click twice" symptom.
    ///
    /// Retried rather than fired once: the window has only just been ordered on
    /// screen, and the first `makeKey()` can be a no-op.
    private func takeKey(attempt: Int = 0) {
        guard panel.isVisible else { return }
        panel.makeKey()

        if panel.isKeyWindow {
            Log.write("panel became key after \(attempt) attempt(s)")
            return
        }
        guard attempt < 10 else {
            Log.write("panel never became key (appActive=\(NSApp.isActive))")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.takeKey(attempt: attempt + 1)
        }
    }

    private func hidePanel() {
        removeEventMonitor()
        panel.orderOut(nil)
    }

    /// Screen origin for the panel: centred under the status item, nudged back
    /// inside the screen when the icon sits near an edge.
    ///
    /// Falls back to the top-right corner of the main screen rather than
    /// bailing out — the previous version `return`ed silently when
    /// `button.window` was nil, which made left-click look like it did nothing.
    private func panelOrigin() -> NSPoint {
        let size = panel.frame.size
        let gap: CGFloat = 6

        if let button = statusItem.button, let window = button.window {
            let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
            return clamped(
                NSPoint(x: frame.midX - size.width / 2, y: frame.minY - size.height - gap),
                size: size,
                screen: window.screen
            )
        }

        Log.write("panelOrigin: button.window unavailable, using fallback")
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSPoint(x: 120, y: 120)
        }
        return clamped(
            NSPoint(x: screen.frame.maxX - size.width - 8,
                    y: screen.frame.maxY - 26 - size.height - gap),
            size: size,
            screen: screen
        )
    }

    private func clamped(_ point: NSPoint, size: NSSize, screen: NSScreen?) -> NSPoint {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return point }
        return NSPoint(
            x: min(max(point.x, visible.minX + 8), visible.maxX - size.width - 8),
            y: min(max(point.y, visible.minY + 8), visible.maxY - size.height - 8)
        )
    }

    /// Closes the panel when the user clicks anywhere outside it. Global mouse
    /// monitors don't fire for events delivered to our own app, so clicks
    /// inside the panel are naturally ignored.
    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    // MARK: - Right-click menu

    private func showContextMenu() {
        hidePanel()

        let menu = NSMenu()

        // Batch actions used to live behind the header's ⋯ menu. Now that the
        // status item has a real context menu, they belong here — they're
        // app-level actions, not panel-level ones.
        let launchAll = item("全部启动", #selector(launchAll))
        launchAll.isEnabled = !store.isBatching && store.runningCount < store.totalCount
        menu.addItem(launchAll)

        let stopAll = item("全部停止", #selector(stopAll))
        stopAll.isEnabled = !store.isBatching && store.runningCount > 0
        menu.addItem(stopAll)

        menu.addItem(.separator())
        menu.addItem(item("在 Finder 中打开分身目录", #selector(revealProfiles)))

        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(openSettings), key: ","))
        menu.addItem(item("关于 Antigravity Hub", #selector(openAbout)))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "退出 Antigravity Hub",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // Attach the menu only for the duration of this click: a permanently
        // attached menu would hijack left-click, which must keep opening the
        // panel.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // MARK: - Settings

    /// Settings are a page inside the panel, not a separate window — so this
    /// deep-links into it rather than opening anything.
    @objc private func openSettings() {
        PanelRouter.shared.route = .settings
        showPanel()
    }

    @objc private func openAbout() {
        PanelRouter.shared.route = .about
        showPanel()
    }

    // MARK: - Menu actions

    @objc private func launchAll() {
        store.launchAll()
    }

    @objc private func stopAll() {
        store.stopAll()
    }

    @objc private func revealProfiles() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ProfileEngine.root.path)
    }
}

/// Borderless panel that can take keyboard focus.
///
/// Replaces `NSPopover` purely to get rid of its arrow: `NSPopover` always
/// draws a beak pointing at the anchor rect and exposes no way to hide it, so
/// the material background, the corner radius and the click-outside dismissal
/// are all handled here instead.
final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts a click even when the panel isn't key yet.
///
/// Belt and braces for the "first click does nothing" problem: making the panel
/// key is the real fix, but if anything delays that, `acceptsFirstMouse` lets
/// the click through to the SwiftUI content instead of being eaten by the
/// window-focus pass.
final class PanelHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Clips the panel's background to its rounded outline.
///
/// `NSGlassEffectView.cornerRadius` rounds the material, but the window's opaque
/// region — and with it the window shadow — stays square, which shows up as
/// square corners at the bottom of the panel. A layer mask on the parent clips
/// the whole subtree, including the material, so the outline is rounded no
/// matter what the glass draws.
final class PanelClipView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PanelMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// Append-only log at `~/Library/Logs/AntigravityHub.log`.
///
/// A menu bar app has no console, so its failures are silent by nature — the
/// first cut of the custom panel simply never appeared, with nothing at all to
/// go on. A handful of lines here turns that class of bug into a one-look fix.
enum Log {
    private static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AntigravityHub.log")

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
