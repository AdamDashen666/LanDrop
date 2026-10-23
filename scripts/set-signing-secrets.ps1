# 把个人证书和描述文件上传为 GitHub 仓库 Secrets（只需你本人运行一次，证书换了再运行）。
# 用法（在 App 的仓库目录里运行）:
#   powershell -ExecutionPolicy Bypass -File scripts\set-signing-secrets.ps1
# 也可以给多个仓库设置: -Repo 用户名/仓库名
param(
    [string]$Repo = ""
)
$ErrorActionPreference = "Stop"
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) { $gh = "C:\Program Files\GitHub CLI\gh.exe" }
$repoArgs = @()
if ($Repo) { $repoArgs = @("--repo", $Repo) }

$p12 = (Read-Host "证书 .p12 文件路径（可直接把文件拖进来）").Trim('"', ' ')
$prov = (Read-Host "描述文件 .mobileprovision 路径（可直接把文件拖进来）").Trim('"', ' ')
$secure = Read-Host "证书 .p12 的密码（没有密码直接回车）" -AsSecureString
$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))

[Convert]::ToBase64String([IO.File]::ReadAllBytes($p12)) | & $gh secret set IOS_P12_BASE64 @repoArgs
[Convert]::ToBase64String([IO.File]::ReadAllBytes($prov)) | & $gh secret set IOS_PROFILE_BASE64 @repoArgs
if ($password) { $password | & $gh secret set IOS_P12_PASSWORD @repoArgs }
Write-Host "完成。之后每次构建都会额外产出 *-signed.ipa。" -ForegroundColor Green
