import AppKit
import SwiftUI

struct LogView: View {
    let profileName: String
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var text = ""
    @State private var error: String?
    @State private var isLoading = true
    @State private var isLive = true
    @State private var updatedAt: Date?

    private static let tailLines = 300
    private static let pollInterval: UInt64 = 1_500_000_000

    private var hasNoLogs: Bool {
        error == nil && !isLoading && (text.isEmpty || text.contains("No logs yet"))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        // No height of its own: the panel is a fixed size and every page fills
        // the space between the header and the footer.
        .task { await pollLoop() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("recent_lines".localized(with: Self.tailLines))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let updatedAt {
                Text(updatedAt, style: .time)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if isLoading && text.isEmpty {
                ProgressView().controlSize(.small).scaleEffect(0.55).frame(width: 14)
            }

            Spacer(minLength: 4)

            HeaderIconButton(
                systemImage: isLive ? "pause.fill" : "play.fill",
                help: isLive ? "pause_follow".localized : "resume_follow".localized
            ) {
                isLive.toggle()
                if isLive { Task { await load() } }
            }

            HeaderIconButton(systemImage: "arrow.clockwise", help: "refresh".localized) {
                Task { await load() }
            }

            HeaderIconButton(systemImage: "doc.on.doc", help: "copy_all".localized) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let error {
            messageState(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "read_log_failed".localized,
                detail: error
            )
        } else if hasNoLogs {
            messageState(
                icon: "doc.text",
                tint: .secondary,
                title: "no_logs_yet".localized,
                detail: "no_logs_desc".localized
            )
        } else {
            logText
        }
    }

    private var logText: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .id("logBottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: text) {
                // Follow the tail while live; stay put when the user pauses so
                // scrolling back through a crash trace isn't yanked away.
                guard isLive else { return }
                withAnimation(.linear(duration: 0.12)) {
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
        }
    }

    private func messageState(icon: String, tint: Color, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Loading

    private func pollLoop() async {
        while !Task.isCancelled {
            if isLive { await load() }
            try? await Task.sleep(nanoseconds: Self.pollInterval)
        }
    }

    private func load() async {
        let name = profileName
        // Read the constant here: it lives on a main-actor type and can't be
        // touched from inside the detached task.
        let limit = Self.tailLines

        let output = await Task.detached(priority: .utility) { () -> String in
            guard let profile = ProfileEngine.profile(named: name) else {
                return "分身「\(name)」不存在。"
            }
            return ProfileEngine.logs(of: profile, lines: limit)
        }.value

        await MainActor.run {
            self.text = output
            self.error = nil
            self.isLoading = false
            self.updatedAt = Date()
        }
    }
}
