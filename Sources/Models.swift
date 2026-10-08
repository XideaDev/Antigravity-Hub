import Foundation

/// A managed Antigravity sandbox on disk.
///
/// Layout follows Chromium's own conventions, so nothing about it is specific to
/// any third-party manager:
///
/// ```
/// ~/.antigravity-profiles/<name>/
/// ├── data/            Chromium user data dir (passed via --user-data-dir)
/// ├── home/            fake HOME for that instance
/// ├── logs/            launch logs
/// └── profile.json     metadata written by Antigravity Hub
/// ```
struct Profile: Identifiable, Hashable {
    let name: String
    let directory: URL

    var id: String { name }

    var dataDirectory: URL { directory.appendingPathComponent("data") }
    var homeDirectory: URL { directory.appendingPathComponent("home") }
    var logsDirectory: URL { directory.appendingPathComponent("logs") }
    var metadataFile: URL { directory.appendingPathComponent("profile.json") }
    var geminiDirectory: URL { homeDirectory.appendingPathComponent(".gemini") }
    var tokenFile: URL { geminiDirectory.appendingPathComponent("jetski-standalone-oauth-token") }
}

/// Metadata persisted in `profile.json`.
///
/// The field names match the on-disk format that already exists under
/// `~/.antigravity-profiles`, so sandboxes created before the rename keep
/// working — and keep their signed-in Google account.
struct ProfileMetadata: Codable, Hashable {
    var name: String
    var description: String?
    var symlinkPolicy: String?
    var inheritedFrom: String?
    var createdAt: String?
    var version: Int?
    var lastAppVersion: String?

    enum CodingKeys: String, CodingKey {
        case name, description, version
        case symlinkPolicy = "symlink_policy"
        case inheritedFrom = "inherited_from"
        case createdAt = "created_at"
        case lastAppVersion = "last_app_version"
    }
}

/// The Google account an instance is signed in as, read from its OAuth token.
struct AccountInfo: Hashable {
    let email: String
    let expiresAt: Date?
    let hasRefreshToken: Bool

    /// The stored access token lives about an hour and is renewed automatically,
    /// so it being past its date is normal — only a profile with no refresh
    /// token actually needs attention.
    var isExpired: Bool {
        guard let expiresAt, !hasRefreshToken else { return false }
        return expiresAt < Date()
    }

    /// The stored access token lives about an hour, so "expiring soon" is only
    /// meaningful when nothing can renew it.
    var isExpiringSoon: Bool {
        guard let expiresAt, !hasRefreshToken else { return false }
        return expiresAt < Date().addingTimeInterval(7 * 24 * 3600)
    }
}

/// Everything the UI needs about one profile, assembled by `ProfileEngine`.
struct ProfileSnapshot: Identifiable, Hashable {
    let name: String
    let directory: URL
    let pid: pid_t?
    let account: AccountInfo?
    let metadata: ProfileMetadata
    /// Only filled in when explicitly requested — computing it walks the whole
    /// sandbox, far too slow for the polling loop.
    let size: String?

    var id: String { name }

    var isRunning: Bool { pid != nil }
    var hasAccount: Bool { account != nil }
    var displayAccount: String { account?.email ?? "未绑定 Google 账号" }
    var displaySize: String { size ?? "—" }
    var note: String? { metadata.description }
    var inheritedFrom: String? { metadata.inheritedFrom }
    var isExpired: Bool { account?.isExpired ?? false }
    var isExpiring: Bool { account?.isExpiringSoon ?? false }
    var pidLabel: String { pid.map { "PID \($0)" } ?? "—" }
}

enum EngineError: LocalizedError {
    case antigravityNotFound
    case profileExists(String)
    case profileMissing(String)
    case invalidName(String)
    case alreadyRunning(String)
    case notRunning(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .antigravityNotFound:
            return "找不到 Antigravity.app，请确认它已安装在「应用程序」文件夹。"
        case let .profileExists(name):
            return "已存在同名分身「\(name)」。"
        case let .profileMissing(name):
            return "分身「\(name)」不存在。"
        case let .invalidName(name):
            return "名字「\(name)」不合法：只能用字母、数字与 . _ -，且需以字母或数字开头（最长 64 字符）。"
        case let .alreadyRunning(name):
            return "分身「\(name)」已经在运行。"
        case let .notRunning(name):
            return "分身「\(name)」当前没有运行。"
        case let .launchFailed(detail):
            return "启动失败：\(detail)"
        }
    }
}
