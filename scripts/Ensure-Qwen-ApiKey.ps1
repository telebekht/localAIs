$ErrorActionPreference = "Stop"

$keyFile = "G:\localAI\AI\scripts\qwen-api-key.txt"
if (-not (Test-Path $keyFile)) {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $key = ([BitConverter]::ToString($bytes) -replace "-", "").ToLowerInvariant()
    Set-Content -Path $keyFile -Value $key -Encoding ascii -NoNewline
    Write-Host "Создан новый ключ: $keyFile"
}

$key = (Get-Content $keyFile -Raw).Trim()
if ($key.Length -lt 32) { throw "Ключ слишком короткий: $keyFile" }
Write-Host "API key file: $keyFile"
Write-Host "Для IDEA или Web UI используйте значение из этого файла."
