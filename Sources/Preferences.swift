import AppKit
import ServiceManagement
import SwiftUI

/// UserDefaults keys, kept in one place so the writer and the reader can't drift.
enum PrefKey {
    static let menuBarIcon = "MenuBarIconID"
    static let refreshInterval = "RefreshInterval"
    static let maskAccounts = "MaskAccounts"
    static let language = "AppLanguage"
}

// MARK: - Menu bar glyph

/// A selectable menu bar icon.
///
/// Each entry pairs an idle and an active symbol so the chosen glyph still
/// answers "is anything running?" at a glance — a static icon would lose the
/// only thing the menu bar can tell you without a click.
struct MenuBarGlyph: Identifiable, Hashable {
    let id: String
    let idle: String
    let active: String

    var label: String { "glyph_\(id)".localized }

    func symbol(active isActive: Bool) -> String { isActive ? active : idle }

    /// Labels are kept to two or three characters: the picker renders five
    /// columns inside a 348pt panel, so anything longer truncates.
    static let catalog: [MenuBarGlyph] = [
        .init(id: "squares", idle: "square.on.square", active: "square.on.square.fill"),
        .init(id: "stack", idle: "square.stack.3d.up", active: "square.stack.3d.up.fill"),
        .init(id: "cube", idle: "cube", active: "cube.fill"),
        .init(id: "grid", idle: "circle.grid.2x2", active: "circle.grid.2x2.fill"),
        .init(id: "rects", idle: "rectangle.stack", active: "rectangle.stack.fill"),
        .init(id: "bolt", idle: "bolt", active: "bolt.fill"),
        .init(id: "hex", idle: "circle.hexagongrid", active: "circle.hexagongrid.fill"),
        .init(id: "window", idle: "macwindow", active: "macwindow.on.rectangle"),
        .init(id: "atom", idle: "atom", active: "atom"),
        .init(id: "sparkles", idle: "sparkles", active: "sparkles"),
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
        case .brisk: return "cadence_3s".localized
        case .normal: return "cadence_5s".localized
        case .relaxed: return "cadence_10s".localized
        case .lazy: return "cadence_30s".localized
        case .onOpen: return "cadence_on_open".localized
        }
    }

    var detail: String {
        switch self {
        case .onOpen: return "cadence_detail_on_open".localized
        default: return "cadence_detail_normal".localized
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
            return "login_item_enabled".localized
        case .requiresApproval:
            return "login_item_pending".localized
        case .notRegistered, .notFound:
            return "login_item_disabled".localized
        @unknown default:
            return "login_item_disabled".localized
        }
    }
}
