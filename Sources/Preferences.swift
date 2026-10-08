import AppKit
import ServiceManagement
import SwiftUI

/// UserDefaults keys, kept in one place so the writer and the reader can't drift.
enum PrefKey {
    static let menuBarIcon = "MenuBarIconID"
    static let refreshInterval = "RefreshInterval"
    static let maskAccounts = "MaskAccounts"
}

// MARK: - Menu bar glyph

/// A selectable menu bar icon.
///
/// Each entry pairs an idle and an active symbol so the chosen glyph still
/// answers "is anything running?" at a glance — a static icon would lose the
/// only thing the menu bar can tell you without a click.
struct MenuBarGlyph: Identifiable, Hashable {
    let id: String
    let label: String
    let idle: String
    let active: String

    func symbol(active isActive: Bool) -> String { isActive ? active : idle }

    /// Labels are kept to two or three characters: the picker renders five
    /// columns inside a 348pt panel, so anything longer truncates.
    static let catalog: [MenuBarGlyph] = [
        .init(id: "squares", label: "双叠", idle: "square.on.square", active: "square.on.square.fill"),
        .init(id: "stack", label: "堆叠", idle: "square.stack.3d.up", active: "square.stack.3d.up.fill"),
        .init(id: "cube", label: "立方", idle: "cube", active: "cube.fill"),
        .init(id: "grid", label: "网格", idle: "circle.grid.2x2", active: "circle.grid.2x2.fill"),
        .init(id: "rects", label: "矩形堆", idle: "rectangle.stack", active: "rectangle.stack.fill"),
        .init(id: "bolt", label: "闪电", idle: "bolt", active: "bolt.fill"),
        .init(id: "hex", label: "六边", idle: "circle.hexagongrid", active: "circle.hexagongrid.fill"),
        .init(id: "window", label: "窗口", idle: "macwindow", active: "macwindow.on.rectangle"),
        .init(id: "atom", label: "原子", idle: "atom", active: "atom"),
        .init(id: "sparkles", label: "星芒", idle: "sparkles", active: "sparkles"),
    ]

    static let fallback = catalog[0]

    static var selected: MenuBarGlyph {
        let id = UserDefaults.standard.string(forKey: PrefKey.menuBarIcon) ?? ""
        return catalog.first { $0.id == id } ?? fallback
    }

    static func select(_ glyph: MenuBarGlyph) {
        UserDefaults.standard.set(glyph.id, forKey: PrefKey.menuBarIcon)
    }
}

// MARK: - Refresh cadence

/// How often to re-enumerate the sandboxes. Each tick walks the profiles
/// directory, so this is a real (if small) power trade-off the user should get
/// to make.
enum RefreshCadence: Int, CaseIterable, Identifiable {
    case brisk = 3
    case normal = 5
    case relaxed = 10
    case lazy = 30
    case onOpen = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .brisk: return "3 秒"
        case .normal: return "5 秒"
        case .relaxed: return "10 秒"
        case .lazy: return "30 秒"
        case .onOpen: return "仅打开面板时"
        }
    }

    var detail: String {
        switch self {
        case .onOpen: return "菜单栏图标不会自动更新，只在点开面板时刷新"
        default: return "每次刷新会短暂启动一个 Python 进程（约 150 毫秒）"
        }
    }

    static var current: RefreshCadence {
        let raw = UserDefaults.standard.object(forKey: PrefKey.refreshInterval) as? Int
        return raw.flatMap(RefreshCadence.init(rawValue:)) ?? .normal
    }

    static func select(_ cadence: RefreshCadence) {
        UserDefaults.standard.set(cadence.rawValue, forKey: PrefKey.refreshInterval)
    }
}

// MARK: - Launch at login

/// Thin wrapper over `SMAppService.mainApp`.
///
/// Registration only succeeds for an app that lives in a real Applications
/// folder and is code-signed — ad-hoc is enough in practice, but a build run
/// straight out of `./build` will be rejected, so the failure has to surface
/// instead of silently doing nothing.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS is holding a registration the user still has to approve
    /// in System Settings › General › Login Items.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "已启用，登录时自动启动"
        case .requiresApproval:
            return "等待系统确认 —— 系统设置 › 通用 › 登录项"
        case .notRegistered, .notFound:
            // `.notFound` is what a freshly installed app reports *before* it
            // has ever been registered — verified empirically with a throwaway
            // bundle in ~/Applications, which registered successfully straight
            // from this state. Treating it as an error would scare users away
            // from a feature that actually works.
            return "未启用"
        @unknown default:
            return "未启用"
        }
    }
}
