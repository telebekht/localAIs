$ErrorActionPreference = "Stop"
$cudaBin = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4\bin\x64"
if (-not (Test-Path (Join-Path $cudaBin "cudart64_13.dll"))) {
    $cudaBin = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4\bin"
}
$env:Path = "$cudaBin;" + $env:Path
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"preserve_thinking":true}'

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
Write-Host "MODE: think  PORT: 8001"

& $server --model $model --mmproj $mmproj --host 0.0.0.0 --port 8001 --alias "qwen3.6-35b-a3b-think" --ctx-size 32768 --n-gpu-layers 99 --n-cpu-moe 22 --cache-ram 8192 --parallel 1 --no-mmproj-offload --reasoning on --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --presence-penalty 0.0
