# 健康检查探针 —— 供 start-6004.bat 调用
#   用法: powershell -NoProfile -File health_probe.ps1 -Url http://127.0.0.1:6004/openapi.json
#   退出码: 0 = 就绪, 1 = 未就绪
#
# 单独做成文件而不是内联在 .bat 里，是因为 .bat 中内联 PowerShell
# 需要转义 $ 与引号，极易出错且难排查。
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$TimeoutSec = 3
)

# 绕过系统代理：本机若开着代理软件（如 FlClash），
# 会拦截 127.0.0.1 的请求并返回伪造响应，导致误判。
$env:HTTP_PROXY = ""
$env:HTTPS_PROXY = ""
$env:NO_PROXY = "*"

try {
    $resp = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSec -UseBasicParsing -Proxy $null
    if ($resp.StatusCode -eq 200) { exit 0 }
    exit 1
}
catch {
    exit 1
}
