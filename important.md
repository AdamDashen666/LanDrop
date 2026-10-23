# Important

## 用户偏好
- 用户用中文交流，Windows 电脑，无 Mac。iOS/iPadOS/macOS 的编译、测试、打包一律走 GitHub Actions（macos-latest）。
- 仓库用公开（public）：macOS 构建机对公开仓库免费不限时；私有仓库每月只有约 200 分钟。
- 用户自己给 IPA 签名（自签）：交付未签名 IPA（*-unsigned.ipa）即可，不要催用户上传证书。云端签名（set-signing-secrets.ps1 + resign-ipa.sh）保留为可选，未实测；若启用，代理不得接触证书密码。

## 约定与坑
- Windows 上无法生成 .xcodeproj，工程由 project.yml（XcodeGen）在 CI 上生成；不要提交 .xcodeproj。
- project.yml 的 target/scheme 名（App-iOS、App-macOS、AppTests-*）被 workflow 写死，改名要同时改 build.yml。
- 模拟器型号随 runner 镜像变化，workflow 用 jq 动态挑选 iPhone/iPad，不要写死设备名。
- macOS App 需要 ad-hoc 签名（CODE_SIGN_IDENTITY "-"），否则 Apple 芯片上无法运行。
- 公开仓库的 Artifacts 任何登录用户都能下载（含已签名 IPA），敏感 App 需注意。
- README 分英文（上）和中文（下）两部分，改功能说明时两边同步。
- gh 安装在 C:\Program Files\GitHub CLI\gh.exe，可能不在旧 shell 的 PATH 里。
