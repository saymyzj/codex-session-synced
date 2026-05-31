# Codex Synced

English | [中文](README.md)

Codex Synced is a local Windows / macOS repair tool for Codex conversation history. It helps when conversations still exist on disk but disappear from the Codex UI after switching between the official OAuth flow, OpenAI API key mode, a third-party API, or another custom provider.

Codex Synced reads the active Codex provider, previews the local history records that need alignment, creates a backup, and repairs local visibility data. It is not a cloud sync tool. Everything happens on your machine.

## Windows Download and Usage

1. Download `Codex-Synced-Windows-x64-1.2.0.msi` from the [latest GitHub Release](https://github.com/saymyzj/codex-session-synced/releases/latest).
2. Quit Codex.
3. Install the MSI, then open `Codex Synced` from the Start menu.
4. Review pending changes, choose a backup mode, then apply the repair.
5. Reopen Codex and verify that local history is visible.

The Windows build is now a full desktop app installer. It defaults to `%USERPROFILE%\.codex`, and the directory can be changed in settings. The Release also includes `Codex-Synced-Windows-x64-1.2.0.zip` for users who prefer a manually extracted app directory.

## macOS Download and Install

1. Download `Codex-Synced-macOS-1.0.1.dmg` from the [latest GitHub Release](https://github.com/saymyzj/codex-session-synced/releases/latest).
2. Open the DMG.
3. Drag `Codex Synced.app` into `Applications`.
4. On first launch, if macOS blocks the app, right-click it in Finder, choose `Open`, and confirm.
5. Quit Codex before repairing or restoring local history.

### If macOS says the app is damaged

Codex Synced 1.0.1 is not Apple-notarized yet. If the DMG came from this repository's Release page, remove its quarantine attribute after verifying the download:

```bash
xattr -dr com.apple.quarantine "/Applications/Codex Synced.app"
```

Avoid globally disabling Gatekeeper.

## Highlights

- Detects the active Codex provider automatically.
- Finds the latest local `state_*.sqlite` database.
- Previews SQLite provider rows, rollout metadata, and missing `session_index.jsonl` entries.
- Creates a lightweight or full backup before writing.
- Restores from previous backups when needed.

## Safety

Codex Synced does not modify OAuth tokens, API keys, third-party URLs, provider settings, or message bodies. It only repairs local history visibility data after you review the preview and choose a backup mode.
