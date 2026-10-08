import SwiftUI

struct CreateProfileView: View {
    @EnvironmentObject private var store: ProfileStore
    /// Called with `true` once the profile exists, so the panel can pop back.
    let onFinish: (Bool) -> Void

    @State private var name = ""
    @State private var note = ""
    @State private var inheritConfig = false
    @State private var links: ProfileEngine.SymlinkPolicy = .full
    @State private var launchAfter = false

    private var nameIssue: String? {
        ProfileEngine.nameIssue(name, existing: store.profiles.map(\.name))
    }

    private var canSubmit: Bool {
        !name.isEmpty && nameIssue == nil && !store.isCreating
    }

    var body: some View {
        // Plain VStack rather than `.safeAreaInset(edge: .bottom)`: inside the
        // panel's fixed-height container the inset didn't reserve space, so the
        // action bar overlapped the form and the overflow escaped the rounded
        // corners. A plain stack makes the layout unambiguous.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    nameField
                    noteField
                    inheritanceSection
                    linksSection

                    if let error = store.createError {
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
        .onAppear { store.clearCreateError() }
    }

    // MARK: Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("名字", required: true)
            TextField("例如 work", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .disabled(store.isCreating)
                .onSubmit { if canSubmit { submit() } }

            if let issue = nameIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
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
                .disabled(store.isCreating)
        }
    }

    private var inheritanceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: $inheritConfig) {
                Text("继承宿主配置").font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .disabled(store.isCreating)

            Text("复制编辑器偏好、快捷键与代码片段，并软链继承 Agent Skills 与 MCP 工具。OAuth Token 与账号永不复制。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if inheritConfig {
                Label("Agent Skills 会以软链方式继承，编辑保持同步",
                      systemImage: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 18)
            }
        }
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("链接策略", required: false)
            Picker("", selection: $links) {
                ForEach(ProfileEngine.SymlinkPolicy.allCases) { policy in
                    Text(policy.label).tag(policy)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(store.isCreating)

            Text(links.detail)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if links == .full {
                Label("会把真实的 ~/.ssh 与 ~/.config 暴露给分身内的 Agent",
                      systemImage: "exclamationmark.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
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

    // MARK: Actions

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $launchAfter) {
                Text("创建后立即启动").font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .disabled(store.isCreating)

            Spacer(minLength: 4)

            if store.isCreating {
                ProgressView().controlSize(.small).scaleEffect(0.65)
            }
            SoftButton(title: "取消") { onFinish(false) }
                .disabled(store.isCreating)
            SoftButton(title: "创建", systemImage: "checkmark", prominent: true) { submit() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
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

    private func submit() {
        guard canSubmit else { return }
        let request = ProfileEngine.CreateRequest(
            name: name,
            description: note.trimmingCharacters(in: .whitespaces),
            symlinkPolicy: links,
            inheritHostConfig: inheritConfig,
            launchAfter: launchAfter
        )
        Task {
            let ok = await store.create(request)
            if ok { onFinish(true) }
        }
    }
}
