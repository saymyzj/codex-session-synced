# Codex Synced UI 设计稿

本目录收录根据 [PRODUCT_SPEC.md](../PRODUCT_SPEC.md) 生成的第一版 macOS 桌面应用界面稿。

## 页面

| 文件 | 页面 | 用途 |
| --- | --- | --- |
| `01-repair-home.png` | 会话历史修复 | 展示当前登录态、动态 Provider、待修复数量和修复入口 |
| `02-pending-repairs.png` | 待修复项 | 修复前预览变更并选择轻简备份或全量备份 |
| `03-repair-progress.png` | 修复进度 | 展示扫描、备份、Provider 对齐、索引修复和结果验证 |
| `04-backups.png` | 备份 | 查看本地备份、容量和修复摘要 |
| `05-restore-confirmation.png` | 恢复确认 | 恢复本地备份前进行二次确认 |
| `06-settings.png` | 设置 | 配置语言、Codex 目录、默认备份模式和最大备份数量 |

## 视觉约束

- 中文为默认语言，右上角提供语言切换。
- 使用浅色 macOS 原生风格和单一系统蓝强调色。
- 产品语义是“修复会话历史可见性”，不是云同步、Git 同步或多设备同步。
- 实现时以 PRD 为功能准绳；图片中的展示文本可在开发阶段做一致性校对。
