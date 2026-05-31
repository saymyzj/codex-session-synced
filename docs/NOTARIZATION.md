# macOS 签名与公证 / macOS Signing and Notarization

Codex Synced 的 DMG 可以在本地打包，但要让 macOS Gatekeeper 认可，还需要 Apple Developer Program 账号、Developer ID 证书和 Apple notary service 公证。

## 前提

- 已加入 Apple Developer Program。
- 钥匙串中有 `Developer ID Application` 证书。
- 使用 Xcode 13 或更新版本提供的 `notarytool`。
- 有 Apple ID app-specific password，或 App Store Connect API key。

检查本机证书：

```bash
security find-identity -v -p codesigning
```

## 保存 notarytool 凭据

使用 Apple ID 和 app-specific password：

```bash
xcrun notarytool store-credentials codex-synced-notary \
  --apple-id "APPLE_ID@example.com" \
  --team-id "TEAMID"
```

命令会提示输入 app-specific password。保存后，后续命令只需要引用 `--keychain-profile codex-synced-notary`。

## 签名 app

当前打包脚本支持通过 `CODESIGN_IDENTITY` 注入 Developer ID 签名。证书名通常长这样：

```text
Developer ID Application: Your Name (TEAMID)
```

用证书签名并生成 DMG：

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-dmg.sh
```

脚本会先签名 `dist/Codex Synced.app`，再把它放入 DMG，并对最终 DMG 签名。

如果只想手动签名 app，也可以先正常打包，再执行：

```bash
codesign --force --timestamp --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  "dist/Codex Synced.app"
```

验证签名：

```bash
codesign --verify --strict --verbose=2 "dist/Codex Synced.app"
spctl -a -vv "dist/Codex Synced.app"
```

## 生成 DMG

`./scripts/package-dmg.sh` 会生成带安装指引的 DMG：左侧是 `Codex Synced.app`，右侧是 `Applications` 链接，用户把 app 拖过去即可安装。

如果你先手动签名 app，记得重新生成 DMG，确保 DMG 里包含的是已签名的 app。

## 提交公证

对最终 DMG 提交公证并等待结果：

```bash
xcrun notarytool submit "dist/Codex-Synced-1.0.0.dmg" \
  --keychain-profile codex-synced-notary \
  --wait
```

如果失败，查看日志：

```bash
xcrun notarytool log SUBMISSION_ID \
  --keychain-profile codex-synced-notary
```

## Staple 公证票据

公证通过后，把票据 stapled 到 DMG：

```bash
xcrun stapler staple "dist/Codex-Synced-1.0.0.dmg"
xcrun stapler validate "dist/Codex-Synced-1.0.0.dmg"
```

最后再做 Gatekeeper 检查：

```bash
spctl -a -vv -t open --context context:primary-signature "dist/Codex-Synced-1.0.0.dmg"
```

## English Summary

To notarize Codex Synced, sign the app with a `Developer ID Application` certificate, package it into a DMG, submit the DMG with `xcrun notarytool submit --wait`, then staple and validate the DMG with `xcrun stapler`. The packaging script accepts `CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"` and signs both the app bundle and the final DMG before notarization.

## References

- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: TN3147, Migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)
