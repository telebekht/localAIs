# MedGemma 1.5 4B Q8_0 for the i5-11500 / 32 GB / RTX 3060 Ti 8 GB PC.
# Research aid for lab sheets and images. Not a diagnosis and not a treatment.
# Launch from PowerShell:
# Invoke-WebRequest -Uri "https://raw.githubusercontent.com/telebekht/localAIs/cursor/medgemma-install-964a/scripts/install-medgemma.ps1" -OutFile "$env:USERPROFILE\install-medgemma.ps1"; powershell.exe -NoExit -ExecutionPolicy Bypass -File "$env:USERPROFILE\install-medgemma.ps1"
param(
    [string]$Root = "D:\AI"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Port = 8080
$Threads = 10
$Ctx = 8192
$ModelUrl = "https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF/resolve/main/medgemma-1.5-4b-it-Q8_0.gguf"
$MmprojUrl = "https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF/resolve/main/mmproj-F16.gguf"
$ModelName = "medgemma-1.5-4b-it-Q8_0.gguf"
$MmprojName = "mmproj-F16.gguf"

function Get-CurlFile {
    param([string]$Url, [string]$Dest, [int64]$MinBytes)
    if (Test-Path -LiteralPath $Dest) {
        if ((Get-Item -LiteralPath $Dest).Length -ge $MinBytes) {
            Write-Host "Уже есть: $Dest"
            return
        }
        Remove-Item -LiteralPath $Dest -Force
    }
    $part = "$Dest.part"
    Write-Host "Скачивание: $Url"
    & curl.exe -fL --retry 3 --retry-delay 2 -o $part $Url
    if ($LASTEXITCODE -ne 0) { throw "Не скачалось: $Url" }
    Move-Item -LiteralPath $part -Destination $Dest -Force
}

Write-Host "MedGemma 1.5 4B читает бланк и снимки только как черновик перед врачом."
Write-Host "Она пропускает находки на МРТ и может назвать то, чего на снимке нет."
Write-Host "Диагноз и лечение по её ответу не назначают."
Write-Host ""

$Root = $Root.TrimEnd("\")
$BinDir = Join-Path $Root "llama.cpp\bin"
$ModelDir = Join-Path $Root "models\medgemma"
$Scripts = Join-Path $Root "scripts"
New-Item -ItemType Directory -Force -Path $BinDir, $ModelDir, $Scripts | Out-Null

$Server = Join-Path $BinDir "llama-server.exe"
if (-not (Test-Path -LiteralPath $Server)) {
    $cudaTag = "12.4"
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        $driver = (& nvidia-smi --query-gpu=driver_version --format=csv,noheader | Select-Object -First 1)
        $major = 0
        if ($driver -match "^(\d+)") { $major = [int]$Matches[1] }
        if ($major -ge 580) { $cudaTag = "13.5" }
    } else {
        Write-Host "nvidia-smi не найден. Беру сборку CUDA 12.4."
    }
    Write-Host "Скачиваю llama.cpp Windows CUDA $cudaTag"
    $release = & curl.exe -fsSL "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=5"
    if ($LASTEXITCODE -ne 0) { throw "Не открылся список релизов llama.cpp." }
    $binPattern = 'https://github.com/ggml-org/llama.cpp/releases/download/[^\s"]+/llama-[^\s"]+-bin-win-cuda-' + $cudaTag + '-x64.zip'
    $rtPattern = 'https://github.com/ggml-org/llama.cpp/releases/download/[^\s"]+/cudart-llama-bin-win-cuda-' + $cudaTag + '-x64.zip'
    $binUrl = [regex]::Match($release, $binPattern).Value
    $rtUrl = [regex]::Match($release, $rtPattern).Value
    if (-not $binUrl -or -not $rtUrl) { throw "Не найден архив llama.cpp CUDA $cudaTag." }
    $binZip = Join-Path $BinDir "llama-cuda.zip"
    $rtZip = Join-Path $BinDir "cudart-cuda.zip"
    Get-CurlFile $binUrl $binZip 1000000
    Get-CurlFile $rtUrl $rtZip 1000000
    & tar.exe -xf $binZip -C $BinDir
    & tar.exe -xf $rtZip -C $BinDir
    $found = Get-ChildItem -LiteralPath $BinDir -Recurse -Filter "llama-server.exe" | Select-Object -First 1
    if (-not $found) { throw "В архиве нет llama-server.exe." }
    $payload = @(Get-ChildItem -LiteralPath $BinDir -Recurse -File | Where-Object {
        $_.DirectoryName -ne $BinDir -and ($_.Extension -eq ".exe" -or $_.Extension -eq ".dll")
    })
    foreach ($file in $payload) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $BinDir $file.Name) -Force
    }
    if (-not (Test-Path -LiteralPath $Server)) { throw "Не удалось положить llama-server.exe в $BinDir." }
} else {
    Write-Host "llama-server уже стоит: $Server"
}

$ModelPath = Join-Path $ModelDir $ModelName
$MmprojPath = Join-Path $ModelDir $MmprojName
Get-CurlFile $ModelUrl $ModelPath 3500000000
Get-CurlFile $MmprojUrl $MmprojPath 700000000

$KeyFile = Join-Path $Scripts "medgemma-api-key.txt"
$OldKey = Join-Path $Scripts "biomistral-api-key.txt"
if (-not (Test-Path -LiteralPath $KeyFile)) {
    if (Test-Path -LiteralPath $OldKey) {
        Copy-Item -LiteralPath $OldKey -Destination $KeyFile
    } else {
        $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $bytes = New-Object byte[] 32
        $rng.GetBytes($bytes)
        $text = -join ($bytes | ForEach-Object { $_.ToString("x2") })
        [System.IO.File]::WriteAllText($KeyFile, $text)
    }
}

$Launcher = Join-Path $Scripts "Start-MedGemma.ps1"
@"
`$ErrorActionPreference = "Stop"
`$env:Path = "$BinDir;" + `$env:Path
Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Write-Host "MODEL: $ModelPath"
Write-Host "MMPROJ: $MmprojPath"
Write-Host "KEY: $KeyFile"
& "$Server" --model "$ModelPath" --mmproj "$MmprojPath" --host 0.0.0.0 --port $Port --api-key-file "$KeyFile" --alias "medgemma-1.5-4b" --ctx-size $Ctx --n-gpu-layers 99 --parallel 1 --threads $Threads --temp 0.2 --top-p 0.9 --repeat-penalty 1.05
"@ | Set-Content -LiteralPath $Launcher -Encoding UTF8

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "MedGemma.lnk"))
$lnk.TargetPath = "powershell.exe"
$lnk.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$Launcher`""
$lnk.WorkingDirectory = $Root
$lnk.Save()

try {
    $rule = Get-NetFirewallRule -DisplayName "MedGemma $Port LAN" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName "MedGemma $Port LAN" -Direction Inbound -Protocol TCP -LocalPort $Port -RemoteAddress LocalSubnet -Action Allow | Out-Null
    }
} catch {
    Write-Host "Правило брандмауэра не создано. Для телефона в домашней сети откройте порт $Port только для локальной подсети."
}

Write-Host ""
Write-Host "Ключ: $KeyFile"
Write-Host (Get-Content -LiteralPath $KeyFile -Raw)
Write-Host "Веб: http://127.0.0.1:$Port"
Write-Host "Картинку прикрепляйте кнопкой + . Бланк по одной странице, МРТ несколькими срезами PNG."
Write-Host "Запускаю сервер. Окно не закрывайте."
Write-Host ""

& $Launcher
