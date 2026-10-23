# apple-build-template

Build, test and package iOS / iPadOS / macOS apps from a Windows PC, without a Mac. Write Swift locally, `git push`, and GitHub Actions macOS runners do the rest. (中文说明见下方。)

## What each build produces

- **iOS**: an unsigned IPA (`MyApp-unsigned.ipa`) that you sign with your own Apple ID (e.g. Sideloadly); also a signed IPA if you add a certificate.
- **macOS**: an ad-hoc signed universal (arm64 + x86_64) app as `.zip` and `.dmg`.
- **Tests**: unit tests on iOS and macOS; XCUITest UI tests on both an iPhone and an iPad simulator. If tests fail, no IPA is produced, but screenshots and logs are still uploaded.
- **Debugging output**: launch screenshots, a screenshot for every UI-test step, the app's `print()` output, system logs and the app's crash reports.

## Quick start

```bash
gh repo create MyApp --public --template AdamDashen666/apple-build-template --clone
```

1. In `project.yml`, set `APP_NAME`, `DISPLAY_NAME` and `BUNDLE_ID_BASE`.
2. Write shared code in `App/Sources` (platform-only code in `App/iOS` or `App/macOS`) and replace `App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with your icon.
3. Run `bash scripts/ci-run.sh`. It pushes, waits for the build, downloads the artifacts to `out/<run id>/`, and prints the failing lines if the build breaks.

The Xcode project is generated on CI from `project.yml` by XcodeGen, so you never need Xcode locally. Optional cloud signing: `scripts\set-signing-secrets.ps1` stores your `.p12` certificate and `.mobileprovision` profile in GitHub Secrets.

macOS runners are free and unlimited for public repositories; private repositories get about 200 macOS minutes a month.

---

# 苹果打包模板（在 Windows 上做 iOS / iPadOS / macOS App）

Windows 不能运行 Xcode。这个模板把编译、测试、打包都放到 GitHub Actions 的 macOS 机器上执行：
在本地写 Swift 代码 → `git push` → 云端构建 → 下载产物。

## 每次构建产出

| 产物（Actions 页面 Artifacts） | 内容 |
|---|---|
| `ios-app` | `MyApp-unsigned.ipa`（未签名，可用爱思助手 / Sideloadly 用自己的 Apple ID 签名安装）；配置了证书时还有 `MyApp-signed.ipa`（可直接装到描述文件登记过的 iPhone/iPad） |
| `ios-screenshots` | App 在 iPhone / iPad 模拟器上启动后的截图；`ui/` 下是界面测试每一步的截图；测试失败时 `test-attachments/` 里有失败瞬间的截图 |
| `macos-app` | `MyApp-macOS.zip` / `.dmg`（ad-hoc 签名；首次打开需右键 →“打开”，或在“隐私与安全性”里允许） |
| `ios-logs` / `macos-screenshots-and-logs` | 编译和测试日志、`*-stdout.log`（App 里 `print()` 的输出）、`*-runtime.log`（系统日志）、`crashes/`（崩溃报告） |

单元测试（`Tests/`）在 iOS 和 macOS 上运行；界面自动化测试（`UITests/`，XCUITest）在 iPhone 和 iPad 模拟器上各跑一遍。测试失败则不产出 IPA，但截图和日志照样上传，方便排查。

## 新建一个 App

```bash
gh repo create 我的App名 --public --template AdamDashen666/apple-build-template --clone
```

然后修改 `project.yml` 里的 `APP_NAME`、`DISPLAY_NAME`、`BUNDLE_ID_BASE`，在 `App/Sources` 里写代码，`App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 换成自己的图标。

- 两个平台共用 `App/Sources`；只属于某个平台的代码放 `App/iOS` 或 `App/macOS`，或用 `#if os(iOS)`。
- 单元测试放 `Tests/`；界面测试放 `UITests/`，继承 `UITestCase`，用 `accessibilityIdentifier` 找控件，`snap("步骤名")` 截图。

## 构建并下载

```bash
bash scripts/ci-run.sh
```

推送、等待构建完成、把产物下载到 `out/<构建编号>/`，失败时打印出错的那几行。

## 个人证书签名（可选）

在仓库目录里运行一次（证书文件和密码只会上传到 GitHub Secrets，不会写进代码）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\set-signing-secrets.ps1
```

需要 `.p12` 证书、它的密码和 `.mobileprovision` 描述文件。描述文件是通配（`TEAMID.*`）时保留原 bundle id，否则会自动改成描述文件要求的 bundle id。

## 免费额度

公开仓库使用 macOS 构建机免费且不限时长；私有仓库每月只有约 200 分钟 macOS 额度。

## License / 许可证

[MIT](LICENSE)
