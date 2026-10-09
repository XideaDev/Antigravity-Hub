import Foundation

/// Single source of truth for the menu bar UI.
///
/// Talks to `ProfileEngine` directly — there is no external CLI and no
/// subprocess in the hot path, which is what makes Antigravity Hub a
/// self-contained app rather than a front-end for someone else's tool.
///
/// Deliberately *not* `@MainActor`-annotated so it stays trivially
/// constructible from the app delegate. The contract is instead: **every** touch
/// of `@Published` state goes through `MainActor.run`, including inside
/// `refresh()` — which is reachable from background `Task`s as well as from
/// main-thread timer and button callbacks.
final class ProfileStore: ObservableObject {

    /// Shared because polling must start at app launch, not when the panel is
    /// first opened — the panel is built lazily, so anything hung off its
    /// `onAppear` would leave the menu bar icon stale until the user clicked it.
    static let shared = ProfileStore()

    private init() {}

    @Published private(set) var profiles: [ProfileSnapshot] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var isBatching = false
    @Published private(set) var isCreating = false
    @Published private(set) var isTiling = false

    /// Surfaced inside the create form rather than the footer, so a failed
    /// creation keeps its error next to the input the user has to fix.
    @Published var createError: String?

    /// How often to re-enumerate profiles. Read from preferences on every
    /// reschedule so the Settings picker takes effect without a restart; zero
    /// means "only refresh when the panel opens".
    private var pollInterval: TimeInterval {
        TimeInterval(RefreshCadence.current.rawValue)
    }

    private var pollTimer: Timer?
    private var noticeTimer: Timer?

    var runningCount: Int { profiles.filter(\.isRunning).count }
    var totalCount: Int { profiles.count }
    var stoppedCount: Int { max(0, totalCount - runningCount) }
    var antigravityMissing: Bool { ProfileEngine.antigravityAppURL == nil }

    var statusSummary: String {
        if antigravityMissing { return "未找到 Antigravity" }
        if profiles.isEmpty { return "暂无分身" }
        return "\(runningCount) / \(totalCount) 运行中"
    }

    // MARK: - Lifecycle

    func startPolling() {
        Task.detached(priority: .utility) {
            ProfileEngine.ensureCLIScriptsReconciled()
        }
        refresh()
        schedulePollTimer()
    }

    /// Re-reads the cadence preference and reschedules. Called when the user
    /// changes it in Settings.
    func restartPolling() {
        schedulePollTimer()
        refresh()
    }

    private func schedulePollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil

        let interval = pollInterval
        guard interval > 0 else { return }   // "仅打开面板时"

        // .common mode so the timer keeps firing while the panel is open.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Reading

    func refresh() {
        Task {
            let alreadyRunning = await MainActor.run { self.isRefreshing }
            if alreadyRunning { return }
            await MainActor.run { self.isRefreshing = true }

            // Enumeration hits the filesystem and shells out to `ps`, so keep it
            // off the main thread.
            let snapshots = await Task.detached(priority: .userInitiated) {
                ProfileEngine.allProfiles().map { ProfileEngine.snapshot(of: $0) }
            }.value

            let sorted = snapshots.sorted { lhs, rhs in
                if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            await MainActor.run {
                self.profiles = sorted
                self.errorMessage = nil
                self.isRefreshing = false
            }
        }
    }

    /// Per-profile detail including on-disk size. Walks the whole sandbox, so it
    /// is fetched on demand — never from the polling loop.
    func details(of name: String) async -> ProfileSnapshot? {
        guard let profile = ProfileEngine.profile(named: name) else { return nil }
        return await Task.detached(priority: .utility) {
            ProfileEngine.snapshot(of: profile, includeSize: true)
        }.value
    }

    // MARK: - Per-profile actions

    func launch(_ snapshot: ProfileSnapshot) {
        act(name: snapshot.name, verb: "启动") { try await ProfileEngine.launch($0) }
    }

    func stop(_ snapshot: ProfileSnapshot) {
        act(name: snapshot.name, verb: "停止") { try await ProfileEngine.stop($0) }
    }

    func delete(_ snapshot: ProfileSnapshot) {
        act(name: snapshot.name, verb: "删除") { try await ProfileEngine.remove($0) }
    }

    private func act(
        name: String,
        verb: String,
        _ work: @escaping (Profile) async throws -> Void
    ) {
        Task {
            guard let profile = ProfileEngine.profile(named: name) else {
                let message = EngineError.profileMissing(name).localizedDescription
                await MainActor.run { self.errorMessage = message }
                return
            }
            await MainActor.run { _ = self.busy.insert(name) }
            do {
                try await work(profile)
                await MainActor.run {
                    self.busy.remove(name)
                    self.showNotice("已\(verb) \(name)")
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    self.busy.remove(name)
                    self.errorMessage = message
                }
            }
            self.refresh()
        }
    }

    // MARK: - Create

    /// Returns true on success. Creating copies config trees and can take a
    /// moment, so the caller keeps the form open and shows a spinner.
    func create(_ request: ProfileEngine.CreateRequest) async -> Bool {
        await MainActor.run {
            self.isCreating = true
            self.createError = nil
        }
        do {
            try await ProfileEngine.create(request)
            await MainActor.run {
                self.isCreating = false
                self.showNotice("已创建 \(request.name)")
            }
            refresh()
            return true
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                self.isCreating = false
                self.createError = message
            }
            return false
        }
    }

    func clearCreateError() {
        createError = nil
    }

    // MARK: - Edit

    /// Renames, re-describes or re-policies an existing profile. Returns the
    /// failure message rather than throwing so the form can show it inline next
    /// to the field that caused it.
    func update(
        _ snapshot: ProfileSnapshot,
        name: String,
        description: String,
        policy: ProfileEngine.SymlinkPolicy
    ) async -> Result<Void, Error> {
        guard let profile = ProfileEngine.profile(named: snapshot.name) else {
            return .failure(EngineError.profileMissing(snapshot.name))
        }

        let edits = ProfileEngine.ProfileEdits(
            name: name,
            description: description,
            symlinkPolicy: policy
        )

        do {
            let updated = try await Task.detached(priority: .userInitiated) {
                try ProfileEngine.update(profile, with: edits)
            }.value
            await MainActor.run { self.showNotice("已保存 \(updated.name)") }
            refresh()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Batch actions

    func launchAll() {
        let targets = profiles.filter { !$0.isRunning }.map(\.name)
        guard !targets.isEmpty else { return }
        batch(targets, verb: "启动")
    }

    func stopAll() {
        let targets = profiles.filter(\.isRunning).map(\.name)
        guard !targets.isEmpty else { return }
        batch(targets, verb: "停止")
    }

    /// Sequential on purpose: each launch spins up a full Electron app, and
    /// firing them all at once makes macOS throttle the window animations.
    private func batch(_ names: [String], verb: String) {
        guard !isBatching else { return }
        isBatching = true

        Task {
            var failures: [String] = []
            for name in names {
                await MainActor.run { _ = self.busy.insert(name) }
                do {
                    guard let profile = ProfileEngine.profile(named: name) else { continue }
                    if verb == "启动" {
                        try await ProfileEngine.launch(profile)
                    } else {
                        try await ProfileEngine.stop(profile)
                    }
                } catch {
                    failures.append(name)
                }
                await MainActor.run { _ = self.busy.remove(name) }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            // Immutable copy so the sendable closure below captures a `let`.
            let failed = failures
            let succeeded = names.count - failed.count
            await MainActor.run {
                self.isBatching = false
                if failed.isEmpty {
                    self.showNotice("已\(verb) \(succeeded) 个分身")
                } else {
                    self.errorMessage = "\(verb)失败：\(failed.joined(separator: "、"))"
                }
            }
            self.refresh()
        }
    }

    // MARK: - Window tiling

    func tileWindows() {
        guard !isTiling else { return }
        isTiling = true
        Task {
            do {
                let outcome = try await Task.detached(priority: .userInitiated) {
                    try ProfileEngine.tileWindows()
                }.value
                await MainActor.run {
                    self.isTiling = false
                    switch outcome {
                    case .tiled: self.showNotice("已平铺 Antigravity 窗口")
                    case .noWindows: self.showNotice("没有找到 Antigravity 窗口")
                    }
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    self.isTiling = false
                    self.errorMessage = message
                }
            }
        }
    }

    // MARK: - Notices

    /// Must be called on the main actor — it mutates `@Published` state and
    /// schedules a `Timer` on the main run loop.
    func showNotice(_ text: String) {
        notice = text
        noticeTimer?.invalidate()
        let timer = Timer(timeInterval: 2.4, repeats: false) { [weak self] _ in
            self?.notice = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        noticeTimer = timer
    }

    func dismissError() {
        errorMessage = nil
    }
}
