# Codex Synced

中文 | [English](#english)

Codex Synced 是一个 macOS 本地修复工具，用来解决切换 Codex Provider 后“历史会话突然不可见”的问题。

当你在 Codex 官方 OAuth、OpenAI API Key、第三方 API 或自定义 Provider 之间切换时，本地历史里记录的 Provider 可能和当前登录态不一致。Codex Synced 会读取当前 Codex Provider，预览需要修复的本地记录，并在备份后把历史会话重新对齐到当前环境。

它不是云同步工具，也不会上传你的会话。所有扫描、备份、修复都发生在本机。

![Codex Synced 首页](docs/screenshots/home-zh.png)

## 下载与安装

1. 前往 [GitHub Releases](https://github.com/saymyzj/codex-session-synced/releases) 下载 `Codex-Synced-1.0.0.dmg`。
2. 双击打开 DMG。
3. 将 `Codex Synced.app` 拖入 `Applications`。
4. 第一次打开时，如果 macOS 提示来自未验证开发者，请在 Finder 中右键点击应用，选择“打开”，再确认打开。
5. 使用前请先退出 Codex，避免本地状态文件正在被写入。

### macOS 提示“无法验证”或“已损坏”怎么办？

Codex Synced 1.0.0 暂未经过 Apple 公证。macOS Gatekeeper 可能会把未公证的下载 app 标记为“无法打开”“无法验证开发者”，甚至显示“已损坏并无法打开”。这通常是下载隔离属性触发的安全拦截，不代表 app 文件真的损坏。

建议按下面顺序处理：

1. 确认 DMG 来自本项目的 [GitHub Releases](https://github.com/saymyzj/codex-session-synced/releases)。
2. 可选：校验下载文件的 SHA256，应与 Release 页面一致：

```bash
shasum -a 256 ~/Downloads/Codex-Synced-1.0.0.dmg
```

3. 先尝试 Apple 推荐的方式：在 Finder 中进入 `Applications`，右键点击 `Codex Synced.app`，选择“打开”，再确认打开。
4. 如果仍然被拦截，打开“系统设置” -> “隐私与安全性”，在“安全性”区域点击“仍要打开”或“打开”。
5. 如果提示“Codex Synced.app 已损坏，无法打开”，可以移除该 app 的下载隔离属性后再打开：

```bash
xattr -dr com.apple.quarantine "/Applications/Codex Synced.app"
```

如果你还没有拖入 `Applications`，也可以把命令里的路径换成 DMG 里或下载目录里的 app 路径。最稳妥的做法是在终端输入 `xattr -dr com.apple.quarantine ` 后，把 `Codex Synced.app` 从 Finder 拖到终端窗口自动填入路径。

不建议使用 `sudo spctl --master-disable` 这类全局关闭 Gatekeeper 的做法；它会降低整台 Mac 的安全保护。只对确认来源的这个 app 移除 quarantine 更克制。

参考资料：

- [Apple：安全打开 Mac 上的 App](https://support.apple.com/en-ca/102445)
- [Apple：打开来自未知开发者的 Mac App](https://support.apple.com/en-euro/guide/mac-help/mh40616/mac)
- [Apple：App 已被修改或损坏](https://support.apple.com/guide/mac-help/the-app-has-been-modified-or-damaged-mh40619/mac)

## 适合谁

- 你切换过 Codex 的官方 OAuth、OpenAI API Key 或第三方 API Provider。
- 你确认历史会话文件仍在本地，但 Codex 界面里看不到。
- 你希望先看清楚会改哪些记录，再决定是否修复。
- 你希望修复前自动备份，并且可以从备份恢复。

## 主要功能

- 自动识别当前 Codex Provider。
- 自动发现本地 `state_*.sqlite`，不写死具体数据库文件名。
- 预览 SQLite Provider 记录、rollout metadata 和 `session_index.jsonl` 缺失项。
- 修复前创建轻简备份或全量备份。
- 轻简备份保存必要回滚数据，全量备份额外保存 sessions。
- 支持从历史备份恢复。
- 中文优先，同时提供 English 界面。

## 使用流程

1. 打开 Codex Synced。
2. 查看首页识别到的 Provider、状态库和待修复数量。
3. 进入“待修复项”，确认变更预览。
4. 选择“轻简备份”或“全量备份”。
5. 点击“备份并修复”。
6. 修复完成后重新打开 Codex，历史会话会按当前 Provider 重新显示。

![待修复项预览](docs/screenshots/pending-repairs-zh.png)

## 备份与恢复

每次真正写入前，Codex Synced 都会先创建备份。你可以在“备份”页查看已有备份，并在需要时恢复。

![备份管理](docs/screenshots/backups-zh.png)

默认保留：

- 轻简备份：5 份
- 全量备份：3 份

这些数量可以在设置中调整。

![设置](docs/screenshots/settings-zh.png)

## 安全边界

Codex Synced 的目标很窄：只修复会话历史的本地可见性。

它不会：

- 修改 OAuth Token
- 修改 API Key
- 修改第三方 API URL
- 修改 Provider 配置
- 修改会话正文
- 上传任何本地历史或配置

它会：

- 读取当前 Codex 配置中的根级 `model_provider`
- 读取本地状态数据库和会话索引
- 在你确认后更新必要的 Provider 可见性字段
- 在写入前创建可恢复备份

## 常见问题

### 为什么需要先退出 Codex？

Codex 运行时可能正在读写本地状态文件。为了避免写入冲突，修复和恢复前需要先退出 Codex。

### 应该选轻简备份还是全量备份？

日常修复建议使用轻简备份，它保存恢复所需的关键文件，速度更快、占用更少。若你希望额外保存 sessions 目录，可以选择全量备份。

### 它会同步到云端吗？

不会。Codex Synced 只在本机工作，不提供云同步，也不会上传会话内容。

### 没有待修复项怎么办？

说明当前本地历史已经和当前 Provider 对齐。之后如果切换 Provider，可以重新扫描。

## English

Codex Synced is a local macOS repair tool for Codex conversation history. It helps when conversations still exist on disk but disappear from the Codex UI after switching between the official OAuth flow, OpenAI API key mode, a third-party API, or another custom provider.

Codex Synced reads the active Codex provider, previews the local history records that need alignment, creates a backup, and then repairs local visibility data. It is not a cloud sync tool. Everything happens on your Mac.

## Download and Install

1. Download `Codex-Synced-1.0.0.dmg` from [GitHub Releases](https://github.com/saymyzj/codex-session-synced/releases).
2. Open the DMG.
3. Drag `Codex Synced.app` into `Applications`.
4. On first launch, if macOS blocks the app, right-click it in Finder, choose “Open”, and confirm.
5. Quit Codex before repairing or restoring local history.

### If macOS says the app is damaged

Codex Synced 1.0.0 is not Apple-notarized yet. Gatekeeper may block it with an “unidentified developer”, “cannot be verified”, or “damaged and can’t be opened” message. For downloads from this repository’s GitHub Releases, this is usually caused by the quarantine attribute rather than a broken app bundle.

Try these steps in order:

1. Make sure the DMG came from the official GitHub Releases page.
2. Optionally verify the SHA256 checksum:

```bash
shasum -a 256 ~/Downloads/Codex-Synced-1.0.0.dmg
```

3. In Finder, open `Applications`, right-click `Codex Synced.app`, choose “Open”, and confirm.
4. If it is still blocked, open System Settings -> Privacy & Security, then use “Open Anyway” in the Security section.
5. If macOS says the app is damaged, remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine "/Applications/Codex Synced.app"
```

Avoid globally disabling Gatekeeper with commands such as `sudo spctl --master-disable`. Removing quarantine from this one verified app is a narrower workaround.

## Highlights

- Detects the active Codex provider automatically.
- Finds the latest local `state_*.sqlite` database.
- Previews SQLite provider rows, rollout metadata, and missing `session_index.jsonl` entries.
- Creates a lightweight or full backup before writing.
- Restores from previous backups when needed.
- Provides both Chinese and English UI.

## Safety

Codex Synced does not modify OAuth tokens, API keys, third-party URLs, provider settings, or message bodies. It only repairs local history visibility data after you review the preview and choose a backup mode.

## Basic Workflow

1. Open Codex Synced.
2. Review the detected provider and pending repair count.
3. Open “Pending Repairs” and inspect the preview.
4. Choose “Lightweight” or “Full” backup.
5. Click “Back Up and Repair”.
6. Reopen Codex and check your history.
