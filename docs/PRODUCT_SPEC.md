# Codex Synced 功能设计

## 1. 产品定位

Codex Synced 是一个 macOS 桌面应用，用于修复 Codex 在切换官方 OAuth
认证和第三方 API 中转站后出现的会话历史不可见问题。

本项目中的“同步”特指：

> 将本地 Codex 历史会话的 Provider 字段动态对齐到当前
> `config.toml` 使用的 Provider，使历史会话重新出现在当前模式下。

它不是云同步、Git 同步或多设备同步工具。

## 2. 问题背景

Codex 会按照 `model_provider` 对本地历史会话分桶展示：

| 使用模式 | `config.toml` 根级 `model_provider` | 新会话 Provider |
| --- | --- | --- |
| 官方 OAuth 认证 | 通常不存在 | `openai` |
| 第三方 API 中转站 | `custom` 或其他值 | 对应配置值 |

用户通过 CC Switch 切换模式后，Codex 只展示当前 Provider 桶中的历史。
另一个桶中的会话仍然存在，但在侧边栏中看起来像“丢失”。

## 3. 核心目标

1. 自动识别当前 Codex Provider。
2. 扫描本地历史会话，统计待修复项。
3. 在用户确认后创建备份。
4. 将历史 Provider 动态对齐到当前 Provider。
5. 修复必要的历史可见性索引。
6. 修复完成后允许用户直接打开 Codex。

## 4. Provider 判定规则

应用只读取 `config.toml` 根级字段，不读取任何 section 内的同名字段。

```text
如果根级存在 model_provider：
    使用该值，例如 custom

如果根级不存在 model_provider：
    默认使用 openai
```

必须忽略此类嵌套字段：

```toml
[mcp_servers.example]
model_provider = "openai_http"
```

否则官方 OAuth 模式可能被错误识别成 `openai_http`。

应用可以展示实际认证类型：

- `OpenAI OAuth`
- `OpenAI API Key`
- `第三方 API`

但修复目标始终由当前根级 Provider 判定规则决定。

## 5. 扫描范围

应用自动识别实际的 `state_*.sqlite`，不得写死 `state_5.sqlite`。

扫描范围：

```text
~/.codex/config.toml
~/.codex/state_*.sqlite
~/.codex/session_index.jsonl
~/.codex/sessions/**/rollout-*.jsonl
~/.codex/archived_sessions/**/rollout-*.jsonl
```

如用户设置了 `CODEX_HOME`、`CODEX_SQLITE_HOME` 或 `sqlite_home`，应用应优先
使用对应目录。

## 6. 修复范围

### 6.1 Provider 动态对齐

用户确认后，应用执行：

1. 更新状态库中的：

```text
threads.model_provider
```

2. 更新普通会话和归档会话 rollout 文件第一行中的：

```text
session_meta.payload.model_provider
```

3. 保持会话正文不变。

### 6.2 可见性兼容修复

为兼容旧数据和 Codex Desktop 的历史索引，应用应检查并按需修复：

```text
threads.has_user_event
threads.cwd
threads.thread_source
session_index.jsonl 缺失条目
```

`session_index.jsonl` 只补充缺失条目，不覆盖已有条目的用户数据。

### 6.3 明确禁止修改

应用不得修改：

- OAuth Token
- API Key
- 第三方中转站 URL
- CC Switch Provider 配置
- 会话正文
- Codex.app 本体

## 7. 备份设计

每次存在实际待修复项时，必须先创建备份。若扫描结果为零，不创建备份。

用户可以选择两种备份模式。

### 7.1 轻简备份

默认模式，默认最多保留 `5` 份。

保存：

- 完整 `state_*.sqlite`
- 存在时保存对应 `-wal` 和 `-shm`
- `config.toml`
- `session_index.jsonl`
- 必要的全局状态小文件
- 每个待改 rollout 文件的原始第一行 metadata
- 备份描述文件

不重复保存会话正文。因为 Provider 修复只改 rollout 第一行，回滚时恢复原始第一行即可。

### 7.2 全量备份

默认最多保留 `3` 份。

除轻简备份内容外，额外保存：

- 完整 `sessions`
- 完整 `archived_sessions`
- 与修复有关的本地状态文件

适用于首次使用、重大版本升级后或用户主动要求更强灾备的场景。

### 7.3 轮换规则

- 两种模式分别维护最大备份数量。
- 用户可以修改两个上限。
- 新备份成功后，自动删除该模式中最旧的超额备份。
- 删除前必须确认新备份完整可读。

## 8. 安全约束

1. Codex 正在运行时不得直接写入状态库。
2. 检测到 Codex 正在运行时，提示用户：
   - `退出 Codex 并继续修复`
   - `取消`
3. 修复前展示 dry-run 摘要。
4. 修复失败时停止打开 Codex，并展示错误和日志位置。
5. 状态库和 rollout 修改必须支持回滚。
6. 日志不得记录 OAuth Token、API Key 或完整敏感 URL。

## 9. 页面设计

界面使用中文为默认语言，提供 `中文 / English` 切换。视觉风格遵循 macOS
原生应用审美，布局简洁，避免数据库管理器式界面。

### 9.1 首页：修复状态

展示：

- 当前认证方式
- 当前 Provider
- Codex 本地目录
- 当前状态库
- 最近一次修复时间
- 当前扫描状态
- 最近备份记录

主操作：

- `扫描待修复项`
- `立即修复`
- `查看待修复项`
- `打开备份目录`
- `打开 Codex`

当没有待修复项时，主状态显示：

```text
会话历史已对齐
```

### 9.2 待修复项

展示修复前 dry-run 摘要：

| 项目 | 数量 |
| --- | ---: |
| 待修改 Provider 的 rollout 文件 | 动态统计 |
| 待修改的 SQLite 记录 | 动态统计 |
| 待补充的索引条目 | 动态统计 |
| 当前目标 Provider | 当前配置值 |

底部操作：

- `备份并修复`
- `取消`

### 9.3 备份

展示：

- 备份时间
- 备份模式
- 目标 Provider
- 大小
- 修复摘要

操作：

- `恢复此备份`
- `打开备份目录`

恢复操作必须二次确认。

### 9.4 设置

保留以下设置：

- 界面语言
- Codex 本地目录
- SQLite 目录
- 默认备份模式：`轻简备份 / 全量备份`
- 轻简备份最大数量，默认 `5`
- 全量备份最大数量，默认 `3`
- 修复完成后自动打开 Codex

## 10. 完整用户流程

```text
用户通过 CC Switch 切换 Provider
        ↓
打开 Codex Synced
        ↓
应用读取当前 Provider 并执行 dry-run
        ↓
展示待修复摘要
        ↓
用户点击“备份并修复”
        ↓
创建轻简或全量备份
        ↓
对齐 SQLite、rollout metadata 和必要索引
        ↓
验证修复结果
        ↓
打开 Codex
```

## 11. 第一版交付范围

第一版必须具备：

- Provider 自动识别
- `state_*.sqlite` 自动识别
- dry-run 扫描
- Provider 动态对齐
- 可见性兼容修复
- 轻简备份
- 全量备份
- 两种备份数量上限和自动轮换
- 备份恢复
- 中英文界面
- DMG 安装包

暂不包含：

- 云端同步
- GitHub 数据同步
- 多设备同步
- 修改 CC Switch 配置
- 修改 Codex.app 本体
- 自动调整旧会话时间排序

## 12. 后续评估项

Codex Desktop 某些版本只预加载最近一页会话。即使历史数据已修复，较旧项目仍可能
因为前端分页策略暂时不出现在侧边栏。

第一版不自动修改会话时间排序。后续可单独评估“历史可见性增强”功能，并明确展示
它会改变最近会话排序。
