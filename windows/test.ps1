# 端到端测试：在临时目录里起一个 LanDrop（LANDROP_HOME），用 HTTP 请求验证收发和安全检查。
# 用法：pwsh windows/test.ps1   （先退出正在运行的局域网互传，否则端口冲突）
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) "landrop-test-$(Get-Random)"
$recv = Join-Path $root 'recv'
New-Item -ItemType Directory $root | Out-Null
$token = 'testtoken'
@{ $token = @{ Name = 'TestPhone'; Id = 'test-device'; Receive = $true } } | ConvertTo-Json | Set-Content "$root\devices.json"

dotnet build "$PSScriptRoot\LanDrop" -c Release --nologo -v q | Out-Null
$exe = Get-ChildItem "$PSScriptRoot\LanDrop\bin\Release" -Recurse -Filter LanDrop.exe | Select-Object -First 1
$env:LANDROP_HOME = $root
$proc = Start-Process $exe.FullName -PassThru
$base = 'http://127.0.0.1:47380'

function Send($kind, $name, $body, $tok = $token) {
    Invoke-WebRequest "$base/send" -Method Post -SkipHttpErrorCheck -Body ([Text.Encoding]::UTF8.GetBytes($body)) -Headers @{
        'X-Token' = $tok; 'X-Kind' = $kind; 'X-File-Name' = [uri]::EscapeDataString($name)
    }
}
function Check($ok, $what) { if (-not $ok) { throw "FAIL: $what" }; "ok   $what" }
$auth = @{ 'X-Token' = $token }

try {
    for ($i = 0; $i -lt 50; $i++) {
        try { Invoke-WebRequest "$base/inbox" -Headers $auth | Out-Null; break } catch { Start-Sleep -Milliseconds 200 }
    }

    Check ((Send text '' '你好 hello').StatusCode -eq 200) '发文本'
    Check ((Get-Content (Get-ChildItem $recv -Filter '文本 *.txt').FullName -Raw -Encoding utf8) -eq '你好 hello') '文本内容正确'
    Check ((Send file '报告 a&b.txt' 'one').StatusCode -eq 200) '发文件（中文和 & 文件名）'
    Check ((Send file '报告 a&b.txt' 'two').StatusCode -eq 200) '同名再发'
    Check ((Get-Content "$recv\报告 a&b.txt" -Raw) -eq 'one' -and (Get-Content "$recv\报告 a&b (1).txt" -Raw) -eq 'two') '同名不覆盖'
    Check ((Send file '..\..\evil.txt' 'x').StatusCode -eq 200 -and (Test-Path "$recv\evil.txt") -and -not (Test-Path "$root\evil.txt")) '路径穿越被挡住'
    Check ((Send file 'b.txt' 'x' 'wrong').StatusCode -eq 401 -and -not (Test-Path "$recv\b.txt")) '错误 token 被拒'
    Check (-not (Get-ChildItem $recv -Filter '*.part' -Force)) '没有残留临时文件'
    # 设备 id 会写进“发送到”快捷方式的参数，带空格等字符必须直接拒绝（不弹配对通知）
    Check ((Invoke-WebRequest "$base/pair" -Method Post -SkipHttpErrorCheck -Headers @{ 'X-Device-Name' = 'x'; 'X-Device-Id' = 'a%20b'; 'X-Receive' = '1' }).StatusCode -eq 400) '配对拒绝非法设备 id'

    $lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
    $local = @{ device = 'test-device'; paths = @("$root\out.txt"); text = 'hi phone' } | ConvertTo-Json
    Check ((Invoke-WebRequest "http://${lan}:47380/local/send" -Method Post -ContentType 'application/json' -Body $local -SkipHttpErrorCheck).StatusCode -eq 403) "局域网地址 $lan 调 /local/send 被拒"

    Set-Content "$root\out.txt" 'to phone' -NoNewline
    Check ((Invoke-WebRequest "$base/local/send" -Method Post -ContentType 'application/json' -Body $local).StatusCode -eq 200) '本机入队'
    # Invoke-RestMethod 把 JSON 数组当一个对象输出，不能再套 @()
    $inbox = Invoke-RestMethod "$base/inbox" -Headers $auth
    Check ($inbox.Count -eq 2 -and ($inbox | Where-Object kind -eq 'text').text -eq 'hi phone') 'inbox 有文本和文件'
    $file = $inbox | Where-Object kind -eq 'file'
    $bytes = (Invoke-WebRequest "$base/item/$($file.id)" -Headers $auth).Content
    Check ([Text.Encoding]::UTF8.GetString($bytes) -eq 'to phone') '下载文件内容正确'
    Check ((Invoke-WebRequest "$base/inbox" -SkipHttpErrorCheck).StatusCode -eq 401) '不带 token 不能看 inbox'
    foreach ($it in $inbox) { Invoke-WebRequest "$base/ack/$($it.id)" -Method Post -Headers $auth | Out-Null }
    Check ((Invoke-RestMethod "$base/inbox" -Headers $auth).Count -eq 0) 'ack 后队列清空'
    Check (Test-Path "$root\SendTo\TestPhone（局域网互传）.lnk") '生成了“发送到”快捷方式'
    "全部通过"
}
finally {
    Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}
