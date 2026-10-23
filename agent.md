# Agent handoff

## 目标
局域网互传：iPhone/iPad ⇄ Windows 传文件和文本。仓库 https://github.com/AdamDashen666/LanDrop（公开，从 apple-build-template 创建）。
- iOS（`App/`、`ShareExt/`）：App 内选文件 / 相册 / 输文本发到电脑；系统分享菜单扩展；App 在前台时接收电脑发来的东西。
- Windows（`windows/LanDrop/`）：托盘程序。收到后 3 秒没传完在左上角显示进度条（完成/失败淡出），传完弹系统通知（复制 / 打开目录）；右键"发送到"和托盘"发送剪贴板"发往手机。

## 关键设计
- 协议（HTTP，端口 47380，Bonjour `_landrop._tcp`）定义在 `windows/LanDrop/Program.cs` 顶部注释；iOS 端在 `App/Shared/Link.swift`。
- 手机只当 HTTP 客户端：电脑→手机是电脑排队、App 在前台时每 2 秒 `GET /inbox` 拉取。
- 配对：`/pair` 让电脑弹"允许/拒绝"通知，允许后发 token；App 和分享扩展各自配对一次（没用 App Group）。
- `/local/send` 只接受本机回环请求（否则局域网里谁都能读电脑文件）。

## 当前状态
- iOS 代码已写，CI 构建中/待验证。
- Windows 端待写。

## 下一步
- Windows 端实现 + `windows/test.ps1`；iOS CI 通过并看截图；真机测试由用户完成。
