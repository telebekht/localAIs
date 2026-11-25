# MedGemma 1.5 4B Q8_0 на i5-11500, 32 ГБ ОЗУ, RTX 3060 Ti 8 ГБ.
#
# Что делает за один запуск:
#   1. Берёт уже стоящий llama-server или скачивает готовую сборку CUDA.
#   2. Скачивает веса Q8_0 и файл зрения mmproj. Без второго файла картинки не читаются.
#   3. Кладёт ключ доступа, ярлык на рабочий стол и сразу запускает сервер.
#
# Модель читает бланк и снимки только как черновик перед врачом.
# На МРТ она пропускает часть находок и может назвать то, чего на снимке нет.
# Диагноз и лечение по её ответу не назначают.
#
# Запуск из PowerShell одной строкой. В PowerShell имя curl — это Invoke-WebRequest,
# поэтому здесь вызывается curl.exe.
# Invoke-WebRequest -Uri "https://raw.githubusercontent.com/telebekht/localAIs/cursor/medgemma-install-964a/scripts/install-medgemma.ps1" -OutFile "$env:USERPROFILE\install-medgemma.ps1"; powershell.exe -NoExit -ExecutionPolicy Bypass -File "$env:USERPROFILE\install-medgemma.ps1"
#
# Другой диск: powershell.exe -ExecutionPolicy Bypass -File .\install-medgemma.ps1 -Root "E:\AI"
param(
    [string]$Root = "D:\AI"
)

$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 иначе может отказаться от HTTPS.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 8080 — страница http://127.0.0.1:8080. Контекст 8192 оставляет место под картинку в 8 ГБ.
# 10 потоков: у i5-11500 их 12, два остаются Windows.
$Port = 8080
$Threads = 10
$Ctx = 8192
$ModelUrl = "https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF/resolve/main/medgemma-1.5-4b-it-Q8_0.gguf"
$MmprojUrl = "https://huggingface.co/unsloth/medgemma-1.5-4b-it-GGUF/resolve/main/mmproj-F16.gguf"
$ModelName = "medgemma-1.5-4b-it-Q8_0.gguf"
$MmprojName = "mmproj-F16.gguf"

# Повторный запуск не качает файл заново, если он уже не меньше ожидаемого размера.
# Обрезок от оборванной загрузки удаляется. curl.exe, не команда curl из PowerShell.
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

# Сервер от BioMistral в D:\AI уже подходит: ту же сборку второй раз не качаем.
$Server = Join-Path $BinDir "llama-server.exe"
if (-not (Test-Path -LiteralPath $Server)) {
    # CUDA 13.5 требует драйвер 580 или новее. На более старом драйвере берём 12.4.
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
    # DLL CUDA должны лежать рядом с exe, иначе сервер молча не запускается.
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

# Q8_0 — самый точный квант этой модели, который вместе с mmproj входит в 8 ГБ.
# Порог размера отсекает оборванный файл: целый Q8_0 около 4,1 ГБ, mmproj около 0,85 ГБ.
$ModelPath = Join-Path $ModelDir $ModelName
$MmprojPath = Join-Path $ModelDir $MmprojName
Get-CurlFile $ModelUrl $ModelPath 3500000000
Get-CurlFile $MmprojUrl $MmprojPath 700000000

# Тот же ключ, что уже вставлен в браузер для BioMistral. Новый создаётся, только если старого нет.
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

# Поле System Message на веб-странице попадает только в чат, которого ещё не было.
# Поэтому фраза «отвечай по-русски» вшита в каждый вопрос пользователя.
# Шаблон — тот же Gemma, что лежит в файле модели, плюс эта фраза.
$Template = Join-Path $Scripts "medgemma-ru.jinja"
$templateText = @'
{{ bos_token }}
{%- if messages[0]['role'] == 'system' -%}
    {%- if messages[0]['content'] is string -%}
        {%- set first_user_prefix = messages[0]['content'] + '

' -%}
    {%- else -%}
        {%- set first_user_prefix = messages[0]['content'][0]['text'] + '

' -%}
    {%- endif -%}
    {%- set loop_messages = messages[1:] -%}
{%- else -%}
    {%- set first_user_prefix = '' -%}
    {%- set loop_messages = messages -%}
{%- endif -%}
{%- for message in loop_messages -%}
    {%- if (message['role'] == 'user') != (loop.index0 % 2 == 0) -%}
        {{ raise_exception('Conversation roles must alternate user/assistant/user/assistant/...') }}
    {%- endif -%}
    {%- if (message['role'] == 'assistant') -%}
        {%- set role = 'model' -%}
    {%- else -%}
        {%- set role = message['role'] -%}
    {%- endif -%}
    {{ '<start_of_turn>' + role + '
' + (first_user_prefix if loop.first else '') }}
    {%- if message['role'] == 'user' -%}
Отвечай только по-русски. Латинские названия можно оставить, пояснение пиши по-русски. Не ставь диагноз и не назначай лечение.

    {%- endif -%}
    {%- if message['content'] is string -%}
        {{ message['content'] | trim }}
    {%- elif message['content'] is iterable -%}
        {%- for item in message['content'] -%}
            {%- if item['type'] == 'image' -%}
                {{ '<start_of_image>' }}
            {%- elif item['type'] == 'text' -%}
                {{ item['text'] | trim }}
            {%- endif -%}
        {%- endfor -%}
    {%- elif message['content'] -%}
        {{ raise_exception('Invalid content type') }}
    {%- endif -%}
    {{ '<end_of_turn>
' }}
{%- endfor -%}
{%- if add_generation_prompt -%}
    {{ '<start_of_turn>model
' }}
{%- endif -%}
'@
# Без метки BOM: парсер шаблона llama.cpp спотыкается о первые три байта UTF-8.
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($Template, $templateText, $utf8)

# --jinja обязателен до --chat-template-file, иначе свой шаблон не примется.
# Температура 0.2 меньше выдумывает цифры на бланке. Повторный штраф 1.05 не даёт зациклиться.
$Launcher = Join-Path $Scripts "Start-MedGemma.ps1"
@"
# Запуск MedGemma. Картинки идут через --mmproj, русский ответ через шаблон.
# Окно не закрывать: в нём работает сервер. Второй llama-server в 8 ГБ не помещается.
`$ErrorActionPreference = "Stop"
`$env:Path = "$BinDir;" + `$env:Path
Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Write-Host "MODEL: $ModelPath"
Write-Host "MMPROJ: $MmprojPath"
Write-Host "KEY: $KeyFile"
& "$Server" --jinja --chat-template-file "$Template" --model "$ModelPath" --mmproj "$MmprojPath" --host 0.0.0.0 --port $Port --api-key-file "$KeyFile" --alias "medgemma-1.5-4b" --ctx-size $Ctx --n-gpu-layers 99 --parallel 1 --threads $Threads --temp 0.2 --top-p 0.9 --repeat-penalty 1.05
"@ | Set-Content -LiteralPath $Launcher -Encoding UTF8

# Ярлык на рабочем столе запускает тот же файл после перезагрузки.
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "MedGemma.lnk"))
$lnk.TargetPath = "powershell.exe"
$lnk.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$Launcher`""
$lnk.WorkingDirectory = $Root
$lnk.Save()

# 0.0.0.0 слушает домашнюю сеть. Правило пускает только LocalSubnet, не весь интернет.
# Без прав администратора установка продолжится, правило просто не создастся.
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
Write-Host "После запуска откройте новый чат: старый диалог уже на английском, модель его продолжит."
Write-Host "Запускаю сервер. Окно не закрывайте."
Write-Host ""

& $Launcher
