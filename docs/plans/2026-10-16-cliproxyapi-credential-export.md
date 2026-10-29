# CLIProxyAPI 凭证一键导出与专属代理配置实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 AntigravityHub 中为分身（以及主宿主）提供一键生成与复制标准 CLIProxyAPI 格式凭据 JSON 的功能，改造主面板复制按钮，并在设置面板中提供专属代理配置开关与输入项。

**Architecture:** 
1. 在 `ProfileEngine` 中新增 `generateCLIProxyJSON(for snapshot: ProfileSnapshot) -> String?`，负责解析本地 OAuth 令牌（`jetski-standalone-oauth-token`），提取 `access_token`、`refresh_token`、`email` 等核心字段，并注入 `project_id: "aicode-consumers"`。
2. 在 `Preferences` 与 `SettingsView` 中增加专属代理字段的配置项（开关 + 代理地址输入框），若开启，生成 JSON 时自动附加 `"proxy_url"`。
3. 改造主面板 `ProfileCard` 账号栏的一键复制按钮，使其一键复制生成的标准 JSON，同时在右键菜单与详情面板中提供“复制 CLIProxyAPI 凭据 JSON”与“复制纯邮箱”的独立选项。
4. 更新中英文多语言资源，并重新编译打包验证。

**Tech Stack:** Swift, SwiftUI, AppKit (`NSPasteboard`, `UserDefaults`), macOS Native Sandbox Engine.

---

### Task 1: 扩展 Preferences 与配置键

**Files:**
- Modify: `Sources/Preferences.swift:5-12`

**Step 1: 添加专属代理设置键**
在 `PrefKey` 中添加：
```swift
static let enableCLIProxyDedicatedProxy = "EnableCLIProxyDedicatedProxy"
static let cliProxyDedicatedProxyURL = "CLIProxyDedicatedProxyURL"
```

**Step 2: 验证编译**
Run: `./build.sh`
Expected: 编译通过

---

### Task 2: 在 ProfileEngine 中实现 CLIProxyAPI 凭据 JSON 生成

**Files:**
- Modify: `Sources/ProfileEngine.swift`

**Step 1: 编写 JSON 组装逻辑**
在 `ProfileEngine` 中实现方法：
```swift
static func generateCLIProxyJSON(for profile: ProfileSnapshot) -> String?
```
逻辑：
1. 定位并读取 `profile.directory` 对应的 `tokenFile`（对于宿主则定位 `~/.gemini/jetski-standalone-oauth-token`）。
2. 从 JSON Envelope 中解析出 `token`（内含 `access_token`、`refresh_token` 等）以及 `id_token`（或 snapshot 的 `account?.email`）。
3. 校验 `refresh_token` 是否存在。若无有效令牌则返回 `nil`。
4. 构建导出字典：
   - `"type"`: `"antigravity"`
   - `"email"`: email
   - `"access_token"`: accessToken（如果存在）
   - `"refresh_token"`: refreshToken
   - `"project_id"`: `"aicode-consumers"`
5. 检查 `UserDefaults` 中的 `PrefKey.enableCLIProxyDedicatedProxy` 与 `PrefKey.cliProxyDedicatedProxyURL`：
   若开启且 URL 非空，则向字典写入 `"proxy_url": proxyURL`。
6. 使用 `JSONSerialization.data(withJSONObject:options: [.prettyPrinted, .sortedKeys])` 导出 UTF-8 字符串。

**Step 2: 验证编译**
Run: `./build.sh`
Expected: 编译通过

---

### Task 3: 在 SettingsView 中添加专属代理设置选项

**Files:**
- Modify: `Sources/SettingsView.swift`

**Step 1: 在设置面板通用区增加代理开关与输入框**
1. 绑定 `@AppStorage(PrefKey.enableCLIProxyDedicatedProxy) private var enableDedicatedProxy = false`
2. 绑定 `@AppStorage(PrefKey.cliProxyDedicatedProxyURL) private var dedicatedProxyURL = ""`
3. 在 `generalSection` 下方卡片区添加：
   - 包含专属代理开关的 `card`
   - 当开启时展开输入框的 `card`，提供 TextField 和清除按钮
   - 配套的说明 `hint`

**Step 2: 验证编译**
Run: `./build.sh`
Expected: 编译通过

---

### Task 4: 改造主面板 ProfileCard 及详情页的复制功能

**Files:**
- Modify: `Sources/OverviewWindow.swift`
- Modify: `Sources/Views.swift`

**Step 1: 改造 OverviewWindow.swift 中的 copyButton**
1. 将 `copyButton` 点击动作改为：
   - 调用 `ProfileEngine.generateCLIProxyJSON(for: profile)`
   - 若生成成功，写入 `NSPasteboard` 并展示 `cliproxy_json_copied` 提示
   - 若失败，降级为复制纯账号邮箱并展示提示
2. 更新 Tooltip 文本为 `"copy_cliproxy_json_hint".localized`。

**Step 2: 丰富右键菜单与详情页**
1. 在 `OverviewWindow.swift` 的卡片右键菜单中增加：
   - `Label("copy_cliproxy_json".localized, systemImage: "doc.on.clipboard")`
   - 保留原有的 `Label("copy_account".localized, systemImage: "person.crop.circle")`
2. 在 `ProfileDetailPane` 的操作栏（`actions`）中同样添加复制 JSON 按钮。
3. 在 `Views.swift`（菜单栏浮层小面板）的快捷按钮中做同样适配。

**Step 3: 验证编译**
Run: `./build.sh`
Expected: 编译通过

---

### Task 5: 添加中英文国际化文本并完整构建

**Files:**
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Resources/en.lproj/Localizable.strings`

**Step 1: 增加以下多语言 Key**
- `copy_cliproxy_json`
- `copy_cliproxy_json_hint`
- `cliproxy_json_copied`
- `cliproxy_proxy_setting`
- `cliproxy_proxy_hint`
- `proxy_url_placeholder`
- `dedicated_proxy_url`

**Step 2: 完整编译并打包安装**
Run: `./build.sh --install`
Expected: 编译通过并成功安装到本地应用程序目录。
