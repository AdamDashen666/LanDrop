# Agent handoff

## 目标
局域网互传：iPhone/iPad ⇄ Windows 传文件和文本。仓库 https://github.com/AdamDashen666/LanDrop（公开，从 apple-build-template 创建）。用户说明见 README.md。
- iOS（`App/`、`ShareExt/`）：App 内选文件 / 相册 / 输文本发到电脑；系统分享菜单扩展；App 在前台时接收电脑发来的东西。
- Windows（`windows/LanDrop/`）：托盘程序。收到后 3 秒没传完在左上角显示进度条（完成/失败淡出），传完弹系统通知（复制 / 打开目录）；右键"发送到"和托盘"发送剪贴板"发往手机。

## 关键设计
- 协议（HTTP，端口 47380，Bonjour `_landrop._tcp`）写在 `windows/LanDrop/Program.cs` 顶部注释；iOS 端在 `App/Shared/Link.swift`。
- 手机只当 HTTP 客户端：电脑→手机是电脑排队、App 在前台时每 2 秒 `GET /inbox` 拉取。
- 配对：`/pair` 让电脑弹"允许/拒绝"通知，允许后发 token；App 和分享扩展各自配对一次。
- `/local/send` 只接受本机回环请求（否则局域网里谁都能读电脑文件）。两端 HTTP 客户端都显式不走代理。
- Bonjour 用 dnsapi `DnsServiceRegister`（`Mdns.cs`），已在本机用 `DnsServiceBrowse` 验证能被发现。

## 当前状态
- Windows：`windows/test.ps1` 全部通过；进度条截图确认；通知已送达通知中心（用户机器上没弹横幅，可能是免打扰）；单文件 exe 在 `windows/publish/`（不入库）。
- iOS：首次 CI 单测和 iPhone/iPad 界面测试通过；"不走代理"改动后需再跑一次 CI。
- 未做真机测试（需用户自签安装 IPA）。

## 下一步
- 用户真机测试：发现/配对、收发、分享菜单、相册、大文件进度条、通知按钮、右键发送到。
- 本机有 Mihomo TUN（198.18.0.1），它的地址也会出现在 Bonjour 的 A 记录里；若手机解析到这个地址连不上，再考虑注册时指定局域网 IP。
