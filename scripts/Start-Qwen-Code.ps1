$ErrorActionPreference = "Stop"
$cudaBin = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4\bin\x64"
if (-not (Test-Path (Join-Path $cudaBin "cudart64_13.dll"))) {
    $cudaBin = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4\bin"
}
$env:Path = "$cudaBin;" + $env:Path

$server = "G:\localAI\AI\llama.cpp\build\bin\Release\llama-server.exe"
$modelDir = "G:\localAI\Models\llama\unsloth\Qwen3.6-35B-A3B-GGUF"
$model = (Get-ChildItem $modelDir -Filter "*UD-Q4_K_XL*.gguf" | Select-Object -First 1).FullName
$mmproj = (Get-ChildItem $modelDir -Filter "*mmproj*.gguf" | Select-Object -First 1).FullName
if (-not (Test-Path $server)) { throw "llama-server.exe not found: $server" }
if (-not $model) { throw "GGUF not found in $modelDir" }
if (-not $mmproj) { throw "mmproj not found in $modelDir" }

$outDir = Split-Path $server
foreach ($dll in "cudart64_13.dll", "cublas64_13.dll", "cublasLt64_13.dll") {
    $src = Join-Path $cudaBin $dll
    if (Test-Path $src) { Copy-Item $src (Join-Path $outDir $dll) -Force }
}

Write-Host "MODEL: $model"
Write-Host "MMPROJ: $mmproj"
Write-Host "MODE: code  PORT: 8002"

& $server --model $model --mmproj $mmproj --host 127.0.0.1 --port 8002 --alias "qwen3.6-35b-a3b-instruct" --ctx-size 32768 --n-gpu-layers 99 --n-cpu-moe 22 --cache-ram 8192 --parallel 1 --no-mmproj-offload --reasoning off --temp 0.7 --top-p 0.8 --top-k 20 --min-p 0.0 --presence-penalty 1.5
