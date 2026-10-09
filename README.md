<div align="center">

# Antigravity Hub

**Native macOS multi-instance manager for Google Antigravity.**

Run several Antigravity windows at the same time — each one signed into its own
Google account, each with its own extensions, settings, history and workspace.

No patched binaries. No modified databases. No external runtime.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](#requirements)
[![Language](https://img.shields.io/badge/Swift-5-orange)](#)
[![Dependencies](https://img.shields.io/badge/runtime%20dependencies-none-brightgreen)](#why-there-is-no-dependency)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

English · [简体中文](README_zh.md)

</div>

---

## The problem

You install Antigravity. You sign in. You start shipping.

Then the second account arrives — a client, a side project, a fresh Gemini Pro
quota — and the IDE suddenly has **no way to handle it**.

One Google account per install. One quota. One set of extensions. One workspace
history. One signing-in-and-out that costs you your session state every time you
switch.

No "add account" button. No profile switcher. No keyboard shortcut that quietly
swaps identities. Just the same login wall, every single time.

## What Antigravity Hub does

It gives every account its own **physically separate instance** of Antigravity,
and puts all of them under one menu bar icon.

```
   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
   │  work        │   │  research    │   │  personal    │
   │  account A   │   │  account B   │   │  account C   │
   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
          │                  │                  │
   ┌──────▼───────┐   ┌──────▼───────┐   ┌──────▼───────┐
   │ data/        │   │ data/        │   │ data/        │
   │ home/        │   │ home/        │   │ home/        │
   │   .gemini/   │   │   .gemini/   │   │   .gemini/   │
   │   token      │   │   token      │   │   token      │
   └──────────────┘   └──────────────┘   └──────────────┘
        isolated           isolated           isolated
```

Launch all three, tile them across your display, and switch between accounts by
switching windows. Nothing is shared, so nothing can collide.

---

## Features

### Multiple accounts, genuinely in parallel

- **True concurrent instances.** Each profile gets its own OS-level process tree —
  not a tab, not a session swap. Launch as many as your machine can hold.
- **`createsNewApplicationInstance` is set on every launch**, so macOS starts a
  fresh application instance instead of handing the request to the one already
  running. Without that flag the second window simply never appears.
- **Keychain arbitration.** Parallel Chromium instances normally fight over a
  single keychain entry and sign each other out. Antigravity Hub makes each
  instance keep its credential inside its own sandbox instead, so three signed-in
  windows stay signed in.

### Isolation that is physical, not simulated

- **Separate `--user-data-dir` per profile.** Extensions, cookies, IndexedDB,
  `localStorage`, cache, history, and the conversation database are separate
  directories on disk. Not filtered views — different files.
- **Separate `HOME` per profile.** Each instance sees its own `.gemini` state, so
  OAuth tokens, account records and settings never cross over.
- **`0700` directories, `0600` metadata.** Nothing is world-readable.

### A real macOS app, not a wrapper

- **Menu bar native.** Lives in the status bar, no Dock icon, no window to manage.
- **Liquid Glass panel** on macOS 26+, classic vibrancy on older releases.
- **Right-click the icon** for app-level actions: launch all, stop all, settings.
- **Keyboard driven** — arrow keys to select, Return to start or stop, `⌘N` to
  create, `⌘R` to refresh, `Esc` to unwind.
- **Ten selectable menu bar icons**, each with an idle and an active glyph so the
  icon still tells you whether anything is running.
- **Launch at login**, one toggle.

### An overview window for when the panel is too small

- **Card grid.** Every profile as a card, grouped by running state, reflowing from
  one to five columns as you resize. Built for comparing accounts side by side
  rather than scrolling a 348pt list.
- **Detail pane.** Select a card and a pane opens with the full metadata — PID,
  sandbox size, path, description — plus a live log tail that refreshes while it
  is open. Reading logs in a full-height window is something the panel simply
  cannot offer.
- **Search** by profile name or Google account, once you have more than a handful.
- **One shared state.** The window and the panel are two views of the same store,
  so stopping a profile in one updates the other instantly. There is no second
  polling loop and no second source of truth.

### Editing a profile — what can and cannot be changed

| Field | Editable | Why |
|---|---|---|
| **Name** | Yes | Renames the sandbox directory and its Spotlight shortcut |
| **Description** | Yes | Free-form metadata, yours to change at any time |
| **Symlink policy** | Yes | Re-applied to the sandbox's `HOME` on save |
| Google account | No | That state lives on Google's side — switch accounts inside Antigravity |
| Created at | No | A historical fact |

- **Renaming is safe.** Before implementing it we scanned a live profile: the
  OAuth token, `settings.json`, `config/` and `.antigravity/` contain no
  reference to the profile's own absolute path, so moving the directory does not
  break the sign-in. Only old conversation records still mention the previous
  path as text, which is cosmetic.
- **Renaming requires the profile to be stopped first.** Moving a directory out
  from under a running Chromium would corrupt its state, so the app refuses
  rather than corrupting.
- **Tightening the policy removes links immediately.** Switching from *full* to
  *minimal* deletes the `.ssh` and `.config` symlinks from that sandbox. This is
  the main lever for shrinking what an agent inside a profile can read — see
  [Security boundary](#security-boundary--please-read).

### Everything else you actually need

| | |
|---|---|
| **Account visibility** | Reads each profile's OAuth token and shows the signed-in Google address right in the list |
| **Batch control** | Start or stop every profile in sequence, spaced so macOS doesn't throttle the window animations |
| **Window tiling** | One click to arrange 1–4 Antigravity windows into a full-screen grid |
| **Per-profile logs** | Tail the newest launch log without leaving the panel |
| **Sandbox sizes** | On-disk footprint per profile, computed on demand |
| **Profile creation** | Symlink policy (full / minimal / none), host-config inheritance, optional auto-launch |
| **Finder integration** | Reveal any sandbox, or generate a Spotlight-searchable `Antigravity (name).app` |

---

## Changelog

### 0.4.0 — CLI Profile Isolation & Multi-Agent Integration
- **Isolated CLI wrappers (`~/.local/bin/agy-<name>`)**: Each profile now generates its own isolated CLI runner with private `HOME`, sanitized `SSH_CONNECTION` (eliminating OAuth 400 OOB errors), and direct terminal integration.
- **AionUi & Multi-Agent native auto-sync**: Automatically registers and maintains isolated profile agents into AionUi backend database (`agent_metadata` and `assistant_definitions`) with zero ACP timeout.
- **Run in Terminal & Quick Actions**: Launch isolated agents in Terminal with one click from card context menus, detail pane, and menu bar drawer chips.
- **Create Profile toggle**: Added "Create Isolated CLI & Multi-Agent Support" toggle with live path preview (`~/.local/bin/agy-<name>`).

### 0.3.0 — Edit profiles
- **Rename** any profile — the sandbox directory and its Spotlight shortcut
  follow. The OAuth token, settings and config never reference the profile's
  own absolute path, so the sign-in survives. Renaming still requires the
  profile to be stopped.
- **Re-describe** profiles in place.
- **Tighten the symlink policy after the fact.** Switching from *full* to
  *minimal* immediately removes the `.ssh` and `.config` symlinks from that
  sandbox — the main lever for shrinking what an agent inside a profile can
  read. Only symlinks are removed; real directories are left alone.

### 0.2.0 — Overview window
- A real resizable window, opened from the panel footer, the right-click menu
  or `⌘⇧O`. Brought forward rather than duplicated if already open.
- Adaptive card grid (one to five columns) grouped by running state, with a
  search field.
- Detail pane on selection: full metadata plus a live log tail that refreshes
  every two seconds while the pane is open.
- Reads the same store as the panel — one source of truth, no second polling
  loop.

### 0.1.0 — First release
- Native Swift multi-instance engine — no CLI, no Python, no helper daemon.
- Menu bar panel with `Liquid Glass` on macOS 26+, classic vibrancy below.
- Right-click menu for app-level actions (start all, stop all, settings).
- Keyboard navigation, batch control, window tiling, per-profile log tail,
  ten selectable menu bar icons, launch at login via `SMAppService`.

## How the sandbox works

Three mechanisms, all of them **public platform behaviour** — nothing here is a
private API, a patched binary, or a tampered database.

### 1. `--user-data-dir` — the storage boundary

Chromium has always supported pointing a single installation at a different user
data directory. Antigravity Hub gives every profile its own:

```
~/Library/...  →  ~/.antigravity-profiles/<name>/data
```

Two instances pointed at two directories share **nothing**: not extensions, not
cookies, not the local store, not the cache, not the chat history database. This
is the same mechanism Chrome uses for its own profiles, applied at the process
level.

### 2. A per-instance `HOME` — the identity boundary

The data directory covers Chromium's state. The `.gemini` state — OAuth tokens,
account records, editor preferences — lives under `HOME`. So each instance gets a
fake `HOME`:

```
HOME = ~/.antigravity-profiles/<name>/home
```

Now the two instances are not just two caches. They are two *identities*.

### 3. `SSH_CONNECTION` — the arbitration trick

This is the part that makes real parallel use work.

Chromium-family apps that embed a language server typically keep their OAuth token
in the **shared login keychain**. Two instances, one keychain entry: the second
instance to refresh overwrites the first, and the first silently gets signed out.
This is the single most common reason naive multi-instance setups fall apart after
a few minutes.

Antigravity Hub launches each instance with `SSH_CONNECTION=1` in its environment.
The bundled language server sees what it believes is a remote session and falls
back to **file-based token storage inside the sandbox** — exactly what a
multi-instance setup needs.

The result: three windows, three accounts, all signed in, all stable.

---

## Why there is no dependency

Antigravity Hub is **pure Swift with zero runtime dependencies**.

- No Python. No Node. No helper daemon. No package manager required to run it.
- The whole application is a single ~1 MB binary in a `.app` bundle.
- Process inspection, sandbox creation, token parsing, window tiling and log tailing
  are all implemented natively.

It also means there is nothing to keep in sync: no separate CLI that can drift out
of version with the UI, and no interpreter that can be broken by an unrelated
`PYTHONPATH` on your machine.

---

## Requirements

- **macOS 14.0** or later (Liquid Glass styling on macOS 26+)
- **Google Antigravity** installed in `/Applications` or `~/Applications`
- **Xcode Command Line Tools** — only to build from source
  (`xcode-select --install`)

---

## Install

Build from source — it takes about ten seconds:

```bash
git clone https://github.com/XideaDev/Antigravity-Hub.git
cd Antigravity-Hub
./build.sh --install
```

`--install` compiles the app, assembles the bundle, ad-hoc signs it, copies it to
`~/Applications` and launches it. Look for the icon in your menu bar.

Other build modes:

```bash
./build.sh          # build into ./build/AntigravityHub.app
./build.sh --run    # build and launch, without installing
```

---

## Usage

**Left-click** the menu bar icon for the profile panel. **Right-click** it for
app-level actions.

### Create your first profile

Click **+** in the panel (or press `⌘N`), give it a name, and pick a symlink
policy:

| Policy | What it links into the sandbox |
|---|---|
| **Full** | `~/.ssh`, `~/.config`, Desktop, Documents, Downloads, shell and git config |
| **Minimal** | git/shell config and common project folders — skips `.ssh` and `.config` |
| **None** | nothing but the keychain bridge |

Tick **inherit host config** to copy editor preferences and symlink your agent
skills into the new sandbox. Credentials and account data are never copied.

Then launch it, and sign in with whichever Google account you want that profile to
own.

### Day to day

| Action | How |
|---|---|
| Start / stop a profile | The button on its row, or select and press `Return` |
| Start / stop everything | Right-click the menu bar icon |
| Expand a profile's details | Click its row — logs, Finder, copy account, delete |
| **Open the overview window** | The overview button in the panel footer, right-click → 打开总览窗口, or `⌘⇧O` |
| Tile all windows | The tile button in the panel footer |
| Change the menu bar icon | Right-click → 设置… → 菜单栏图标 |
| Launch at login | Right-click → 设置… → 通用 |

---

## Security boundary — please read

Antigravity Hub provides **environment isolation**, and it is important not to
mistake that for a security sandbox.

- **What it isolates:** application state and identity. Extensions, cookies,
  local storage, history and OAuth tokens are genuinely separate, so two profiles
  cannot see or corrupt each other's data.
- **What it does not isolate:** the filesystem. With the default **Full** symlink
  policy, the real `~/.ssh` and `~/.config` are symlinked into the sandbox, so
  anything running inside a profile — including an agent — can read them.
- **If that matters to you, choose `Minimal` or `None`** when creating a profile.
  `None` links almost nothing.

Profiles are not a privilege boundary either: every instance runs as your user
account, with your user's permissions.

Sandbox directories are created `0700` and metadata files `0600`, so other users
on the machine cannot read them — but **do not sync `~/.antigravity-profiles` to
cloud storage, and do not commit it to a repository.** It contains live OAuth
tokens in plain text.

---

## Project layout

```
Sources/
├── AntigravityHubApp.swift   AppKit shell: status item, panel, right-click menu
├── ProfileEngine.swift       Sandbox lifecycle: create, launch, stop, inspect
├── ProfileStore.swift        Observable state shared by both surfaces
├── Models.swift              Profile, metadata, account, snapshot types
├── Views.swift               Panel, profile rows, shared control chrome
├── OverviewWindow.swift      Overview window: card grid, detail pane, log tail
├── SettingsView.swift        In-panel settings and about pages
├── CreateProfileView.swift   New-profile form
├── EditProfileView.swift     Rename, re-describe, re-apply the symlink policy
├── LogView.swift             Log tail viewer for the panel
└── Preferences.swift         Preferences, menu bar glyphs, launch-at-login
Resources/Info.plist
build.sh
```

About 3,500 lines of Swift, no third-party packages.

---

## FAQ

**Does it modify Antigravity?**
No. It never touches the binary, the code signature, or any database. It only
launches Antigravity with different arguments and a different `HOME`.

**Will this get my account banned?**
There is nothing to detect. Each instance is an ordinary, unmodified Antigravity
process started by macOS, signing in through Google's normal OAuth flow. The tool
does not intercept, proxy, or replay any traffic.

**Where is my data?**
`~/.antigravity-profiles/<name>/`. Delete the folder and the profile is gone.

**Do I need to sign in again for each profile?**
Once per profile, yes — that is the point. Each one holds its own account.

**Why is the first click sometimes slow?**
The first launch of an instance initialises a fresh Chromium user data directory.
Subsequent launches are fast.

**Windows / Linux?**
No. The sandboxing is portable in principle, but the app is built on AppKit,
`NSStatusItem` and Liquid Glass, and targets macOS only.

---

## Roadmap

### Shipped
- [x] Native multi-instance engine — one Chromium process tree per profile,
  with `createsNewApplicationInstance` and the `SSH_CONNECTION` trick to keep
  OAuth tokens inside each sandbox
- [x] Menu bar panel with `Liquid Glass` on macOS 26+, classic vibrancy below
- [x] Right-click menu, keyboard navigation, batch control, window tiling,
  per-profile log tail, ten menu bar icons, launch at login
- [x] Overview window with adaptive card grid and live log detail pane
- [x] Profile editing — rename, re-describe, tighten the symlink policy
  after the fact

### Next
- [ ] **Signed release builds** — Developer ID + notarization so `Antigravity
  Hub.app` can ship without the "unidentified developer" gate
- [ ] **DMG distribution** — drag-to-Applications installer with an
  e-icon-style background
- [ ] **Homebrew Cask** — `brew install --cask xideadev/antigravity-hub` for
  one-line installation
- [ ] **Localization** — currently English + Simplified Chinese. Add Japanese
  on request.

### Considered, but explicitly not planned
- **Web console.** A browser UI would mean a local HTTP server and a second
  interface to maintain, contradicting the project's native-app,
  zero-dependency positioning. The overview window already covers the one
  thing a 348pt panel cannot do: spreading many profiles across a large
  display.
- **Real Gemini Pro quota display.** Antigravity does not expose this
  programmatically; reverse-engineering an undocumented endpoint is out of
  scope and fragile. The current session-state visibility is enough to know
  whether a profile is healthy.
- **Plugin marketplace.** Out of scope for a single-developer utility; would
  become a maintenance surface of its own.

Have an idea that does not fit any of the above? Open an issue — small
contributions that match the project tone are welcome.

---

## Contributing

Issues and pull requests are welcome. If you are reporting a bug, please include
your macOS version, your Antigravity version, and the contents of
`~/Library/Logs/AntigravityHub.log` around the time of the problem.

---

## License

[MIT](LICENSE) © 2026 Jenson

---

## Disclaimer

Antigravity Hub is an independent, community-built tool. It is **not affiliated
with, endorsed by, or connected to Google LLC**. Google, Antigravity and Gemini are
trademarks of Google LLC. Interface icons are system SF Symbols.

The project contains no code from any third-party Antigravity manager; the sandbox
mechanisms it uses are documented, public behaviour of Chromium and macOS.
