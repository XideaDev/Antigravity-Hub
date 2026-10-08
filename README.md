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

A single Antigravity installation is bound to a single Google account.

That means one quota, one extension set, one workspace history, one set of
credentials. The moment you want a work account *and* a personal account — or you
simply keep hitting Gemini Pro rate limits mid-task — you are stuck signing in and
out, losing your session state every time you switch.

There is no "add account" button. There is no profile switcher.

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

- [x] Native multi-instance engine
- [x] Menu bar panel with Liquid Glass
- [x] Batch control, tiling, logs, launch-at-login
- [x] Overview window with card grid and live log tail
- [ ] Signed release builds

> **On a web console:** there will not be one. A browser UI would mean a local HTTP
> server and a second interface to maintain, and it would contradict the whole
> point of this project — a native app with no runtime dependencies and no
> background service. The overview window covers the one thing a 348pt panel
> cannot do: spreading many profiles across a large display.

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
