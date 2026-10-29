param(
    [Parameter(Position = 0)]
    [ValidateSet("think", "code")]
    [string]$Mode = "think"
)

Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

$target = if ($Mode -eq "code") {
    Join-Path $PSScriptRoot "Start-Qwen-Code.ps1"
} else {
    Join-Path $PSScriptRoot "Start-Qwen-Think.ps1"
}

& $target
