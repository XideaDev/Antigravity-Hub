import SwiftUI

/// Edits the fields a profile actually owns.
///
/// Deliberately narrow: the signed-in Google account belongs to Google, and the
/// creation date is a fact. What is left — name, description, and how much of
/// the real home is exposed inside the sandbox — is everything that is genuinely
/// a property of this profile.
struct EditProfileView: View {
    @EnvironmentObject private var store: ProfileStore
    let profile: ProfileSnapshot
    let onFinish: (Bool) -> Void

    private let originalNote: String
    private let originalPolicy: ProfileEngine.SymlinkPolicy

    @State private var name: String
    @State private var note: String
    @State private var policy: ProfileEngine.SymlinkPolicy
    @State private var isSaving = false
    @State private var error: String?

    init(profile: ProfileSnapshot, onFinish: @escaping (Bool) -> Void) {
        self.profile = profile
        self.onFinish = onFinish

        let resolved = ProfileEngine.SymlinkPolicy(
            rawValue: profile.metadata.symlinkPolicy ?? ""
        ) ?? .full
        originalNote = profile.note ?? ""
        originalPolicy = resolved

        _name = State(initialValue: profile.name)
        _note = State(initialValue: profile.note ?? "")
        _policy = State(initialValue: resolved)
    }

    private var isRenaming: Bool { name != profile.name }

    private var nameIssue: String? {
        guard isRenaming else { return nil }
        return ProfileEngine.nameIssue(name, existing: store.profiles.map(\.name))
    }

    /// Renaming moves the sandbox directory, which would corrupt a running
    /// Chromium. Surface that before the save, not as a failure after it.
    private var blockedByRunning: Bool { isRenaming && profile.isRunning }

    private var hasChanges: Bool {
        isRenaming || note != originalNote || policy != originalPolicy
    }

    private var canSave: Bool {
        !name.isEmpty && nameIssue == nil && !blockedByRunning && hasChanges && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    nameField
                    noteField
                    policySection

                    if let error {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }

            Divider()
            actionsRow
        }
    }

    // MARK: Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("名字", required: true)
            TextField("例如 work", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .disabled(isSaving)
                .onSubmit { if canSave { save() } }

            if blockedByRunning {
                Label(
                    "改名会移动沙箱目录，请先停止这个分身。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            } else if let issue = nameIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isRenaming {
                Label(
                    "会移动沙箱目录。登录状态会保留（凭据不依赖路径），"
                    + "但历史对话记录里会残留旧路径文字。",
                    systemImage: "info.circle"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("描述", required: false)
            TextField("例如 公司业务账号", text: $note)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .disabled(isSaving)
        }
    }

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("链接策略", required: false)
            Picker("", selection: $policy) {
                ForEach(ProfileEngine.SymlinkPolicy.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(isSaving)

            Text(policy.detail)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if policy == .full {
                Label(
                    "会把真实的 ~/.ssh 与 ~/.config 暴露给分身内的 Agent",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            } else if originalPolicy == .full {
                Label(
                    "收紧后，沙箱里已有的 ~/.ssh 与 ~/.config 软链会被移除（真实目录不受影响）",
                    systemImage: "lock.shield"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.red.opacity(0.08)))
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            if isSaving {
                ProgressView().controlSize(.small).scaleEffect(0.65)
                Text("正在保存…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            SoftButton(title: "取消") { onFinish(false) }
                .disabled(isSaving)
            SoftButton(title: "保存", systemImage: "checkmark", prominent: true) { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func fieldLabel(_ text: String, required: Bool) -> some View {
        HStack(spacing: 3) {
            Text(text).font(.system(size: 12, weight: .medium))
            if required {
                Text("*").font(.system(size: 12)).foregroundStyle(.red)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        error = nil
        Task {
            let outcome = await store.update(
                profile,
                name: name,
                description: note,
                policy: policy
            )
            await MainActor.run {
                isSaving = false
                switch outcome {
                case .success: onFinish(true)
                case let .failure(failure): error = failure.localizedDescription
                }
            }
        }
    }
}
