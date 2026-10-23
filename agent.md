# Agent handoff

## 目标
在 Windows 上通过 GitHub Actions（macOS runner）编译、测试、打包 iOS/iPadOS/macOS App。本目录是模板仓库 `apple-build-template`（公开、设为 GitHub template），每个新 App 从它创建独立仓库。全局技能 `C:\Users\Admin\.claude\skills\apple-build\SKILL.md` 记录了以后的完整流程（含测试和排错方法）。

## 关键文件
- `project.yml`：XcodeGen 配置（CI 上生成 .xcodeproj）：App-iOS / App-macOS，单测 AppTests-iOS / AppTests-macOS，界面测试 AppUITests-iOS。
- `UITests/UITestCase.swift`：界面测试基类，`snap()` 通过 `TEST_RUNNER_SCREENSHOT_DIR` 把截图写到 CI 的 `screenshots/ui/`。
- `.github/workflows/build.yml`：iOS job（iPhone+iPad 模拟器上跑单测和界面测试 → 单独启动截图，抓 stdout、系统日志、本 App 的崩溃报告 → 未签名 IPA → 有 Secrets 时重签）；macOS job（单测 → universal Release → zip/dmg → 启动截图 + stdout）。
- `scripts/ci-run.sh`：推送、轮询构建状态、下载产物到 out/<run_id>/；`scripts/resign-ipa.sh`、`scripts/set-signing-secrets.ps1`：可选的云端签名。

## 当前状态
- 已推送到 https://github.com/AdamDashen666/apple-build-template（公开，已设为 template）。
- 已在 CI 上验证：单测、iPhone/iPad 界面测试、截图、print 输出抓取、unsigned IPA、macOS zip/dmg。iOS job 约 20 分钟（界面测试占约 10 分钟），macOS 约 2 分钟。
- 用户选择自签，交付物是未签名 IPA；云端重签路径保留但未实测。

## 下一步
- 新 App 按全局技能 apple-build 的流程从模板创建。
