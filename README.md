# Codex Synced

Codex Synced 是一个 macOS 本地工具，用于在切换 Codex 官方 OAuth 和第三方 API Provider 后，修复会话历史不可见问题。

它会读取当前 `config.toml` 根级 `model_provider`，将本地历史会话 Provider 动态对齐到当前 Provider，并在修改前创建可恢复备份。

## 开发

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

## 打包

```bash
bash scripts/package-dmg.sh
```

产物会生成在：

```text
dist/Codex Synced.dmg
```

## 安全边界

- 不修改 OAuth Token、API Key、第三方 URL。
- 不修改 CC Switch Provider 配置。
- 不修改会话正文。
- 只读取 `config.toml` 根级 `model_provider`，忽略嵌套 section 内同名字段。
- 自动发现实际存在的 `state_*.sqlite`，不写死 `state_5.sqlite`。
