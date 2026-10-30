# Important

## 用户偏好
- 用户用中文交流，Windows 电脑，无 Mac。iOS 的编译、测试、打包走 GitHub Actions（流程见全局技能 apple-build）。
- 仓库公开（macOS 构建机免费）；用户自己签名 IPA，只交付 `*-unsigned.ipa`。

## 约定与坑
- 工程由 project.yml（XcodeGen）在 CI 上生成，不要提交 .xcodeproj；target/scheme 名 App-iOS 等被 build.yml 写死。
- 只做 iOS：macOS target 和 job 已删。改 `windows/**` 或 `*.md` 不触发 CI（paths-ignore），此时 `scripts/ci-run.sh` 会等不到构建。
- Info.plist 里生成不了的键（数组/字典，如 NSBonjourServices、NSExtension）放在 `App/Info.plist`、`App/ShareExt-Info.plist`，其余用 `INFOPLIST_KEY_*`。
- `App/Shared` 同时编进 App 和分享扩展：不能用 `UIApplication` 等扩展禁用的 API。
- 分享扩展不用 App Group（免费 Apple ID 自签容易签不上），所以它和 App 各自配对。
- 分享扩展选 NSItemProvider 类型时要排除 public.url / public.file-url：它们也 conforms 到 public.data，loadFileRepresentation 取到的只是地址的 bplist（曾导致电脑收到名为“文件URL”的小文件）。
- Kestrel 默认请求体上限 30MB，必须设 `MaxRequestBodySize = null`；HttpListener 监听非 localhost 需要管理员，所以用 Kestrel。
