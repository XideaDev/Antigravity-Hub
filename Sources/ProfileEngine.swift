import AppKit
import Foundation

/// Everything Antigravity Hub knows about managing Antigravity instances.
///
/// Clean-room implementation: it drives Antigravity purely through Chromium's
/// public `--user-data-dir` sandboxing plus a per-instance `HOME`, and shares no
/// code with any other multi-instance manager. There is no external CLI or
/// runtime dependency — the app is the whole product.
enum ProfileEngine {

    // MARK: - Locations

    /// Sandbox root. Kept at `~/.antigravity-profiles` because the name is a
    /// plain description of its contents (not a product name), and because
    /// existing sandboxes hold live Google logins that would be lost by moving.
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".antigravity-profiles")
    }

    /// `~/Applications` is where per-instance launch shortcuts live.
    static var applicationsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
    }

    private static let candidateAppPaths = [
        "/Applications/Antigravity.app",
        "~/Applications/Antigravity.app",
    ]

    static var antigravityAppURL: URL? {
        let fm = FileManager.default
        for raw in candidateAppPaths {
            let path = (raw as NSString).expandingTildeInPath
            if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        // Spotlight as a last resort, in case it lives somewhere unusual.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity") {
            return url
        }
        return nil
    }

    // MARK: - Reading

    static func allProfiles() -> [Profile] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { fm.fileExists(atPath: $0.appendingPathComponent("profile.json").path) }
            .map { Profile(name: $0.lastPathComponent, directory: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func profile(named name: String) -> Profile? {
        allProfiles().first { $0.name == name }
    }

    static func snapshot(of profile: Profile, includeSize: Bool = false) -> ProfileSnapshot {
        ProfileSnapshot(
            name: profile.name,
            directory: profile.directory,
            pid: runningPID(of: profile),
            account: account(of: profile),
            metadata: metadata(of: profile),
            size: includeSize ? directorySize(profile.directory) : nil
        )
    }

    static func metadata(of profile: Profile) -> ProfileMetadata {
        guard let data = try? Data(contentsOf: profile.metadataFile),
              let meta = try? JSONDecoder().decode(ProfileMetadata.self, from: data)
        else {
            return ProfileMetadata(name: profile.name)
        }
        return meta
    }

    /// The pid of the instance whose `--user-data-dir` points at this sandbox.
    ///
    /// Matched on the argument rather than the process name so that two windows
    /// of the same app are told apart correctly.
    static func runningPID(of profile: Profile) -> pid_t? {
        runningPIDs(matching: marker(for: profile)).first
    }

    private static func marker(for profile: Profile) -> String {
        "--user-data-dir=\(profile.dataDirectory.standardizedFileURL.path)"
    }

    private static func runningPIDs(matching marker: String) -> [pid_t] {
        guard let output = runTool("/bin/ps", ["-axo", "pid=,args="]) else { return [] }
        var pids: [pid_t] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let split = trimmed.firstIndex(of: " "),
                  let pid = pid_t(trimmed[trimmed.startIndex..<split]) else { continue }
            let arguments = trimmed[trimmed.index(after: split)...]
            if arguments.contains(marker) { pids.append(pid) }
        }
        return pids
    }

    // MARK: - Account

    /// Reads the signed-in Google account out of the instance's OAuth token.
    ///
    /// Two on-disk shapes exist and both must be understood:
    ///
    /// * legacy bare JWT — the whole file is `header.payload.signature`;
    /// * JSON envelope — current Antigravity writes
    ///   `{"token": {...}, "auth_method": ..., "id_token": "<JWT>"}`, where the
    ///   real JWT lives in `id_token`. Splitting the *raw file* on "." yields
    ///   garbage, which is why naive parsing reports "not signed in".
    static func account(of profile: Profile) -> AccountInfo? {
        guard let raw = try? String(contentsOf: profile.tokenFile, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var claims: [String: Any] = [:]
        var hasRefresh = false
        var expiry: Date?

        if let data = trimmed.data(using: .utf8),
           let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let inner = envelope["token"] as? [String: Any] ?? [:]
            hasRefresh = (inner["refresh_token"] as? String)?.isEmpty == false
            if let rawExpiry = inner["expiry"] as? String {
                expiry = parseISO8601(rawExpiry)
            }
            if let idToken = envelope["id_token"] as? String {
                claims = decodeJWTPayload(idToken)
            }
        } else {
            claims = decodeJWTPayload(trimmed)
        }

        guard let email = claims["email"] as? String, !email.isEmpty else { return nil }
        if expiry == nil, let exp = claims["exp"] as? Double {
            expiry = Date(timeIntervalSince1970: exp)
        }
        return AccountInfo(email: email, expiresAt: expiry, hasRefreshToken: hasRefresh)
    }

    private static func decodeJWTPayload(_ jwt: String) -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }
        return json
    }

    private static func parseISO8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: - Size

    /// Walks the sandbox. Slow by nature, so callers must ask for it explicitly
    /// rather than paying for it on every poll.
    static func directorySize(_ url: URL) -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else { return "—" }

        var bytes: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            bytes += Int64(size)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Lifecycle

    static func launch(_ profile: Profile) async throws {
        guard let appURL = antigravityAppURL else { throw EngineError.antigravityNotFound }
        if runningPID(of: profile) != nil { throw EngineError.alreadyRunning(profile.name) }

        let configuration = NSWorkspace.OpenConfiguration()
        // Without this macOS would hand the request to an already-running
        // Antigravity and no second window would appear — the entire point of
        // the app is that each profile gets its own instance.
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [marker(for: profile)]
        configuration.environment = launchEnvironment(for: profile)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: EngineError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// A per-instance `HOME` is what keeps the instances' Gemini state apart.
    ///
    /// `SSH_CONNECTION` is a deliberate lie told to the bundled language server:
    /// when it believes it is running over SSH it keeps its OAuth token in a
    /// file inside the sandbox instead of the shared login keychain. Without it
    /// parallel instances contend over one keychain entry and sign each other
    /// out.
    private static func launchEnvironment(for profile: Profile) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = profile.homeDirectory.path
        environment["SSH_CONNECTION"] = "1"
        environment["PATH"] = (environment["PATH"].map { $0 + ":" } ?? "")
            + "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return environment
    }

    static func stop(_ profile: Profile) async throws {
        let pids = runningPIDs(matching: marker(for: profile))
        guard !pids.isEmpty else { throw EngineError.notRunning(profile.name) }

        // Ask nicely first so Antigravity can flush its workspace state.
        for pid in pids { kill(pid, SIGTERM) }
        if await waitForExit(pids, timeout: 10) { return }

        // Then sweep up whatever is left, including helper processes.
        for pid in runningPIDs(matching: marker(for: profile)) { kill(pid, SIGKILL) }
        _ = await waitForExit(runningPIDs(matching: marker(for: profile)), timeout: 3)
    }

    private static func waitForExit(_ pids: [pid_t], timeout: TimeInterval) async -> Bool {
        guard !pids.isEmpty else { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pids.allSatisfy({ kill($0, 0) != 0 }) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return pids.allSatisfy { kill($0, 0) != 0 }
    }

    static func remove(_ profile: Profile) async throws {
        if runningPID(of: profile) != nil {
            try await stop(profile)
        }
        try FileManager.default.removeItem(at: profile.directory)
        removeShortcut(for: profile.name)
    }

    // MARK: - Creating

    struct CreateRequest {
        var name: String
        var description: String = ""
        var symlinkPolicy: SymlinkPolicy = .full
        var inheritHostConfig = false
        var launchAfter = false
    }

    enum SymlinkPolicy: String, CaseIterable, Identifiable {
        case full, minimal, none

        var id: String { rawValue }

        var label: String {
            switch self {
            case .full: return "完全"
            case .minimal: return "精简"
            case .none: return "不链接"
            }
        }

        var detail: String {
            switch self {
            case .full: return "链接 ~/.ssh、~/.config、Desktop、Documents、Downloads 等全部真实目录"
            case .minimal: return "只链接 git/shell 配置和常用项目目录，跳过 .ssh/.config"
            case .none: return "几乎不链接任何真实目录，仅保留钥匙串桥接"
            }
        }
    }

    static func nameIssue(_ name: String, existing: [String]) -> String? {
        if name.isEmpty { return nil }
        let pattern = "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"
        if name.range(of: pattern, options: .regularExpression) == nil {
            return "只能含字母、数字与 . _ -，且需以字母或数字开头（最长 64 字符）"
        }
        if existing.contains(name) { return "已存在同名分身" }
        return nil
    }

    @discardableResult
    static func create(_ request: CreateRequest) async throws -> Profile {
        let pattern = "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"
        guard request.name.range(of: pattern, options: .regularExpression) != nil else {
            throw EngineError.invalidName(request.name)
        }
        guard !allProfiles().contains(where: { $0.name == request.name }) else {
            throw EngineError.profileExists(request.name)
        }

        let fm = FileManager.default
        let profile = Profile(name: request.name, directory: root.appendingPathComponent(request.name))
        if fm.fileExists(atPath: profile.directory.path) {
            throw EngineError.profileExists(request.name)
        }

        for directory in [profile.directory, profile.dataDirectory, profile.homeDirectory, profile.logsDirectory] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }

        let metadata = ProfileMetadata(
            name: request.name,
            description: request.description.isEmpty ? nil : request.description,
            symlinkPolicy: request.symlinkPolicy.rawValue,
            inheritedFrom: request.inheritHostConfig ? "host" : nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            version: 1,
            lastAppVersion: antigravityVersion()
        )
        try writeMetadata(metadata, to: profile)

        try applySymlinkPolicy(request.symlinkPolicy, to: profile)
        if request.inheritHostConfig {
            inheritHostConfiguration(into: profile)
        }
        createShortcut(for: profile)

        if request.launchAfter {
            try await launch(profile)
        }
        return profile
    }

    /// The fields a profile actually exposes for editing.
    ///
    /// Everything else is either a fact (creation date, version) or lives on
    /// Google's side — the signed-in account cannot be changed here, only by
    /// signing in again inside Antigravity.
    struct ProfileEdits {
        var name: String
        var description: String
        var symlinkPolicy: SymlinkPolicy
    }

    /// Applies edits in place, renaming the sandbox first if asked.
    ///
    /// Renaming is safe: the sandbox's OAuth token, `settings.json`, `config/`
    /// and `.antigravity/` were all verified to contain no self-referential
    /// paths, so the signed-in account survives the move. The only residue is
    /// the old path appearing as text inside historical conversation
    /// transcripts, which is cosmetic.
    @discardableResult
    static func update(_ profile: Profile, with edits: ProfileEdits) throws -> Profile {
        var target = profile
        let trimmedName = edits.name.trimmingCharacters(in: .whitespaces)

        if trimmedName != profile.name {
            let pattern = "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"
            guard trimmedName.range(of: pattern, options: .regularExpression) != nil else {
                throw EngineError.invalidName(trimmedName)
            }
            guard !allProfiles().contains(where: { $0.name == trimmedName }) else {
                throw EngineError.profileExists(trimmedName)
            }
            // Moving the directory out from under a running Chromium would
            // corrupt its state, so require it to be stopped first.
            if runningPID(of: profile) != nil {
                throw EngineError.alreadyRunning(profile.name)
            }

            let destination = root.appendingPathComponent(trimmedName)
            try FileManager.default.moveItem(at: profile.directory, to: destination)
            removeShortcut(for: profile.name)
            target = Profile(name: trimmedName, directory: destination)
        }

        var metadata = metadata(of: target)
        metadata.name = target.name
        metadata.description = edits.description.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : edits.description.trimmingCharacters(in: .whitespaces)
        metadata.symlinkPolicy = edits.symlinkPolicy.rawValue
        try writeMetadata(metadata, to: target)

        try applySymlinkPolicy(edits.symlinkPolicy, to: target)
        createShortcut(for: target)
        return target
    }

    private static func writeMetadata(_ metadata: ProfileMetadata, to profile: Profile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: profile.metadataFile, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: profile.metadataFile.path)
    }

    /// Exposes parts of the real home inside the sandbox via symlinks, and
    /// removes the ones a tightened policy no longer wants.
    ///
    /// Safe to re-run: it is the same routine used at creation, so changing a
    /// profile's policy later reconciles the existing sandbox rather than
    /// rebuilding it.
    private static func applySymlinkPolicy(_ policy: SymlinkPolicy, to profile: Profile) throws {
        let fm = FileManager.default
        let realHome = fm.homeDirectoryForCurrentUser

        // `sensitive` marks the two dot-directories that "minimal" deliberately
        // leaves out, so the policy can be tightened after the fact.
        let entries: [(name: String, sensitive: Bool)] = [
            ("Desktop", false), ("Documents", false), ("Downloads", false),
            (".gitconfig", false), (".bash_profile", false),
            (".bashrc", false), (".zshrc", false),
            (".ssh", true), (".config", true),
        ]

        for entry in entries {
            let destination = profile.homeDirectory.appendingPathComponent(entry.name)
            let wanted = policy == .full || (policy == .minimal && !entry.sensitive)

            if wanted {
                let source = realHome.appendingPathComponent(entry.name)
                guard fm.fileExists(atPath: source.path),
                      !fm.fileExists(atPath: destination.path) else { continue }
                try? fm.createSymbolicLink(at: destination, withDestinationURL: source)
            } else {
                removeIfSymlink(destination)
            }
        }
    }

    /// Removes a path only when it is a symlink.
    ///
    /// The sandbox's `home/` also contains real directories created by
    /// Antigravity itself; deleting those would destroy instance state, so a
    /// policy change must never touch anything but the links we made.
    private static func removeIfSymlink(_ url: URL) {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink
        else { return }
        try? fm.removeItem(at: url)
    }

    /// Copies editor preferences that are safe to share, and symlinks agent
    /// skills. Credentials and account data are never touched.
    private static func inheritHostConfiguration(into profile: Profile) {
        let fm = FileManager.default
        let realGemini = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
        try? fm.createDirectory(at: profile.geminiDirectory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])

        // settings.json is copied with anything credential-shaped stripped out.
        let source = realGemini.appendingPathComponent("settings.json")
        if let raw = try? Data(contentsOf: source),
           let object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] {
            let sensitive = ["jetski-standalone-oauth-token", "google_accounts", "google_account_id",
                             "lastLoginUsername", "oauth_creds", "credentials", "token",
                             "refreshToken", "accessToken"]
            let filtered = object.filter { key, _ in
                let lowered = key.lowercased()
                if sensitive.contains(key) { return false }
                return !lowered.contains("oauth") && !lowered.contains("token")
                    && !lowered.contains("secret") && !lowered.contains("credential")
            }
            if let data = try? JSONSerialization.data(withJSONObject: filtered, options: [.prettyPrinted]) {
                let destination = profile.geminiDirectory.appendingPathComponent("settings.json")
                try? data.write(to: destination, options: [.atomic])
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
        }

        // Agent skills are linked, not copied, so edits stay in sync.
        let skills = realGemini.appendingPathComponent("antigravity")
        let linkedSkills = profile.geminiDirectory.appendingPathComponent("antigravity")
        if fm.fileExists(atPath: skills.path), !fm.fileExists(atPath: linkedSkills.path) {
            try? fm.createSymbolicLink(at: linkedSkills, withDestinationURL: skills)
        }
    }

    private static func antigravityVersion() -> String? {
        guard let appURL = antigravityAppURL,
              let bundle = Bundle(url: appURL) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    // MARK: - Launch shortcut

    /// Builds `~/Applications/Antigravity (<name>).app`, a tiny bundle whose
    /// executable re-launches Antigravity against this sandbox. Gives each
    /// instance a Spotlight-reachable entry point.
    static func createShortcut(for profile: Profile) {
        guard let appURL = antigravityAppURL else { return }
        let fm = FileManager.default
        let bundle = applicationsDirectory.appendingPathComponent("Antigravity (\(profile.name)).app")
        let executable = bundle.appendingPathComponent("Contents/MacOS/launch")
        let iconSource = appURL.appendingPathComponent("Contents/Resources/app.icns")

        try? fm.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"),
                                withIntermediateDirectories: true)
        try? fm.createDirectory(at: bundle.appendingPathComponent("Contents/Resources"),
                                withIntermediateDirectories: true)

        let script = """
        #!/bin/sh
        exec open -n -a "\(appURL.path)" --args "\(marker(for: profile))"
        """
        try? script.write(to: executable, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        if fm.fileExists(atPath: iconSource.path) {
            try? fm.copyItem(at: iconSource,
                             to: bundle.appendingPathComponent("Contents/Resources/app.icns"))
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleName</key><string>Antigravity (\(profile.name))</string>
        <key>CFBundleExecutable</key><string>launch</string>
        <key>CFBundleIdentifier</key><string>dev.antigravityhub.shortcut.\(profile.name)</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleIconFile</key><string>app</string>
        <key>LSUIElement</key><true/>
        </dict></plist>
        """
        try? plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"),
                         atomically: true, encoding: .utf8)
    }

    static func removeShortcut(for name: String) {
        let bundle = applicationsDirectory.appendingPathComponent("Antigravity (\(name)).app")
        try? FileManager.default.removeItem(at: bundle)
    }

    // MARK: - Logs

    static func newestLogFile(of profile: Profile) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: profile.logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        return entries
            .filter { $0.pathExtension == "log" }
            .max { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
    }

    /// Trailing lines of the newest launch log, with ANSI escapes stripped.
    static func logs(of profile: Profile, lines: Int) -> String {
        guard let file = newestLogFile(of: profile) else {
            return "该分身还没有日志。日志会在每次启动时写入。"
        }
        // Read at most the last 128 KB: logs can grow large and only the tail matters.
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 128 * 1024
        let offset = size > window ? size - window : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()

        let text = String(data: data, encoding: .utf8) ?? ""
        let tail = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(max(0, lines))
        return tail.joined(separator: "\n")
    }

    // MARK: - Window tiling

    enum TileOutcome {
        case tiled
        case noWindows
    }

    /// Arranges the open Antigravity windows into a grid based on how many there
    /// are. Requires Accessibility permission, since it drives System Events.
    static func tileWindows() throws -> TileOutcome {
        let script = """
        tell application "Finder"
            set screenBounds to bounds of window of desktop
            set screenWidth to item 3 of screenBounds
            set screenHeight to item 4 of screenBounds
        end tell

        tell application "System Events"
            set targetWindows to {}
            repeat with proc in (every application process whose name contains "Antigravity")
                try
                    repeat with w in (every window of proc)
                        set end of targetWindows to w
                    end repeat
                end try
            end repeat

            set count_ to count of targetWindows
            if count_ is 0 then return "no_windows"

            set menuBarHeight to 30
            set usableHeight to screenHeight - menuBarHeight

            if count_ is 1 then
                set w to item 1 of targetWindows
                set position of w to {80, menuBarHeight + 20}
                set size of w to {screenWidth - 160, usableHeight - 40}
            else if count_ is 2 then
                set halfWidth to (screenWidth / 2) as integer
                repeat with i from 1 to 2
                    set w to item i of targetWindows
                    set position of w to {(i - 1) * halfWidth, menuBarHeight}
                    set size of w to {halfWidth, usableHeight}
                end repeat
            else if count_ is 3 then
                set thirdWidth to (screenWidth / 3) as integer
                repeat with i from 1 to 3
                    set w to item i of targetWindows
                    set position of w to {(i - 1) * thirdWidth, menuBarHeight}
                    set size of w to {thirdWidth, usableHeight}
                end repeat
            else
                set halfWidth to (screenWidth / 2) as integer
                set halfHeight to (usableHeight / 2) as integer
                set slots to {{0, menuBarHeight}, {halfWidth, menuBarHeight}, ¬
                              {0, menuBarHeight + halfHeight}, {halfWidth, menuBarHeight + halfHeight}}
                repeat with i from 1 to 4
                    if i > count_ then exit repeat
                    set w to item i of targetWindows
                    set slot to item i of slots
                    set position of w to slot
                    set size of w to {halfWidth, halfHeight}
                end repeat
            end if
            return "ok"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        let errorData = err.fileHandleForReading.readDataToEndOfFile()
        let outputData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorText = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            // -1743 / "not allowed" is the Accessibility grant being missing,
            // which is by far the most common cause here.
            if errorText.contains("-1743") || errorText.contains("not allowed")
                || errorText.contains("not authorized") || errorText.contains("-25211") {
                throw EngineError.launchFailed("窗口平铺需要「辅助功能」权限，请在 系统设置 › 隐私与安全性 › 辅助功能 中勾选本应用。")
            }
            throw EngineError.launchFailed(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.contains("no_windows") ? .noWindows : .tiled
    }

    // MARK: - Shell helper

    private static func runTool(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
