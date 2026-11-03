# Чек-лист: BioMistral-7B-Instruct Q4_K_M на i5-11500 + 32GB + RTX 3060 Ti 8GB (llama.cpp)

Все команды — **Windows PowerShell**. Этот чек-лист использует реальные пути `G:\localAI`, CUDA 13.4 и Visual Studio 2026. Он заменяет устаревшие примеры с `D:\AI`, CUDA 12.6, `huggingface-cli`, `$PSScriptRoot` в консоли и Cursor.

> **Только исследования.** [BioMistral](https://huggingface.co/BioMistral/BioMistral-7B) не прошла клиническую валидацию. Не используйте её для диагностики, назначения лечения или иных решений о здоровье. Проверяйте факты по первичным источникам и квалифицированному специалисту.

## Что поместится

| Параметр | Значение |
| --- | --- |
| Модель | BioMistral-7B-Instruct, Q4_K_M |
| Диск | ~4.2–4.4 GB |
| GPU | RTX 3060 Ti 8 GB, весь слой на GPU |
| Контекст | Начать с 2048; 4096 — только после проверки VRAM |
| Скорость | ориентир ~55–75 tok/s |
| Сервер | один процесс, порт 8080 |

BioMistral основана на Mistral-7B-Instruct-v0.1. Для медицинских публикаций и тестовых вопросов она лучше работает на английском. Это не coding-модель и не замена Qwen для IDEA.

## Сначала: починить многострочную вставку PowerShell

В старом PSReadLine 2.0 многострочная вставка может попасть в консоль **снизу вверх**. Пока не обновили модуль, вставляйте только однострочные команды из этого файла.

```powershell
Install-Module PSReadLine -Scope CurrentUser -Force -AllowClobber
```

Закройте окно PowerShell, откройте новое. Проверка:

```powershell
(Get-Module PSReadLine).Version
```

Нужна 2.2 или новее.

## Пути этой машины

| Что | Путь |
| --- | --- |
| llama.cpp | `G:\localAI\AI\llama.cpp` |
| Сервер | `G:\localAI\AI\llama.cpp\build\bin\Release\llama-server.exe` |
| Модель | `G:\localAI\Models\llama\BioMistral\BioMistral-7B-GGUF` |
| Скрипты | `G:\localAI\AI\scripts` |
| CUDA | `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4` |

Уже собранный llama.cpp из Qwen-чек-листа подходит: RTX 3060 Ti тоже Ampere `sm_86`.

## Фаза 1 — CUDA и llama.cpp

Пропустите, если существует `G:\localAI\AI\llama.cpp\build\bin\Release\llama-server.exe` и команда ниже показывает `CUDA0`.

```powershell
$bin = "G:\localAI\AI\llama.cpp\build\bin\Release"; & "$bin\llama-server.exe" --list-devices
```

На Visual Studio 18 2026 нужен **CUDA Toolkit 13.4**, не CUDA 12.6. CUDA 12.6 не содержит нужной интеграции для `VC\v180`.

Если сборка нужна заново, сначала в новом PowerShell:

```powershell
$cuda = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4"; $env:CudaToolkitDir = $cuda; $env:CUDA_PATH = $cuda; $env:CUDA_PATH_V13_4 = $cuda; $env:Path = "$cuda\bin\x64;$cuda\bin;" + $env:Path
```

Затем:

```powershell
cd G:\localAI\AI\llama.cpp; if (Test-Path .\build) { Remove-Item -Recurse -Force .\build }; cmake -B build --fresh -T "cuda=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4" -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DCUDAToolkit_ROOT="C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4"; cmake --build build --config Release -j $env:NUMBER_OF_PROCESSORS --target llama-server llama-cli
```

Если `llama-server.exe --version` молчит или Windows просит DLL, скопируйте `cudart64_13.dll`, `cublas64_13.dll`, `cublasLt64_13.dll` из `CUDA\v13.4\bin\x64` рядом с `llama-server.exe`.

## Фаза 2 — скачать BioMistral

Официальный репозиторий GGUF: [BioMistral/BioMistral-7B-GGUF](https://huggingface.co/BioMistral/BioMistral-7B-GGUF).

Команды `huggingface-cli` больше не нужны. Публичная модель скачивается и без входа; для больших/частых скачиваний входите через Python.

```powershell
python -m pip install -U pip "huggingface_hub[cli]" hf-transfer
```

Логин — по желанию:

```powershell
python -c "from huggingface_hub import login; login()"
```

Скачивание Q4_K_M:

```powershell
$dest = "G:\localAI\Models\llama\BioMistral\BioMistral-7B-GGUF"; New-Item -ItemType Directory -Force -Path $dest | Out-Null; $env:HF_HUB_ENABLE_HF_TRANSFER = "1"; python -c @"
from huggingface_hub import snapshot_download
snapshot_download(repo_id='BioMistral/BioMistral-7B-GGUF', local_dir=r'$dest', allow_patterns=['*Q4_K_M*.gguf'])
"@
```

Проверка:

```powershell
Get-ChildItem "G:\localAI\Models\llama\BioMistral\BioMistral-7B-GGUF" -Recurse -Filter "*Q4_K_M*.gguf" | Select-Object Name, @{N='GB';E={[math]::Round($_.Length/1GB,2)}}
```

## Фаза 3 — запуск с ключом и ярлыком

Ниже одна строка: она создаёт случайный API-ключ при первом запуске и поднимает сервер на порту **8080**. Сервер доступен с домашней сети, но каждый запрос к API требует ключ. HTML-страница открывается, однако Web UI потребует ключ в Settings перед отправкой сообщения.

```powershell
$cuda="C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4\bin\x64"; if(-not(Test-Path "$cuda\cudart64_13.dll")){$cuda="C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4\bin"}; $env:Path="$cuda;"+$env:Path; $scripts="G:\localAI\AI\scripts"; New-Item -ItemType Directory -Force -Path $scripts|Out-Null; $keyFile="$scripts\biomistral-api-key.txt"; if(-not(Test-Path $keyFile)){$b=New-Object byte[] 32;$r=[Security.Cryptography.RandomNumberGenerator]::Create();try{$r.GetBytes($b)}finally{$r.Dispose()};([BitConverter]::ToString($b)-replace "-","").ToLowerInvariant()|Set-Content $keyFile -Encoding ascii -NoNewline}; $m=(Get-ChildItem "G:\localAI\Models\llama\BioMistral\BioMistral-7B-GGUF" -Filter "*Q4_K_M*.gguf"|Select-Object -First 1).FullName; if(-not $m){throw "Нет Q4_K_M GGUF"}; & "G:\localAI\AI\llama.cpp\build\bin\Release\llama-server.exe" --model $m --host 0.0.0.0 --port 8080 --api-key-file $keyFile --alias biomistral-7b-instruct --ctx-size 2048 --n-gpu-layers 99 --parallel 1 --threads 10 --temp 0.2 --top-p 0.9 --top-k 40 --min-p 0.05 --repeat-penalty 1.1
```

Успех: `HTTP server listening`. Остановка: Ctrl+C. Порт 8080 занят только пока это окно открыто.

Ключ:

```powershell
Get-Content "G:\localAI\AI\scripts\biomistral-api-key.txt"
```

### VRAM и тюнинг

- Базовый режим: `ctx-size 2048`, `parallel 1`.
- Для 4096 сначала убедитесь через `nvidia-smi`, что VRAM не кончается. В команду добавить `--ctx-size 4096` и `--cache-type-k q8_0 --cache-type-v q8_0`.
- CUDA OOM: верните 2048, закройте браузер/игры, оставьте `parallel 1`.
- Q5_K_M может дать немного качества, но на 8 GB уменьшает запас под KV. Q4_K_M — безопасный старт.

## Фаза 4 — проверить API

Во втором окне PowerShell:

```powershell
$key = Get-Content "G:\localAI\AI\scripts\biomistral-api-key.txt" -Raw; Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/models" -Headers @{Authorization="Bearer $($key.Trim())"}
```

Тестовый запрос одной строкой:

```powershell
$key=(Get-Content "G:\localAI\AI\scripts\biomistral-api-key.txt" -Raw).Trim(); $body='{"model":"biomistral-7b-instruct","messages":[{"role":"user","content":"Which organ produces insulin? A) Liver B) Pancreas C) Spleen D) Kidney. Answer with one letter then a brief rationale."}],"max_tokens":128}'; (Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/chat/completions" -Method Post -ContentType "application/json" -Headers @{Authorization="Bearer $key"} -Body ([Text.Encoding]::UTF8.GetBytes($body))).choices[0].message.content
```

Ожидаемый смысл ответа: `B`, pancreas.

## Телефон, встроенный Web UI

Компьютер и телефон должны быть в одном обычном домашнем Wi-Fi. Гостевая сеть и мобильный интернет не подойдут.

Один раз в PowerShell **от администратора**:

```powershell
New-NetFirewallRule -DisplayName "BioMistral 8080 LAN" -Direction Inbound -Protocol TCP -LocalPort 8080 -RemoteAddress LocalSubnet -Action Allow
```

Узнать IP компьютера:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object IPAddress, InterfaceAlias
```

На телефоне открыть `http://IP_КОМПЬЮТЕРА:8080`. В настройках Web UI вставить содержимое `biomistral-api-key.txt` как API key.

Порт не пробрасывать в интернет. API-ключ защищает запросы, но HTTP в домашней Wi-Fi сети не шифруется.

## IDEA и Cursor

BioMistral — медицинская чат-модель, не модель автодополнения кода. Не назначайте её в IDEA AI Completion. Для IDEA оставьте JetBrains/Mellum или Qwen2.5-Coder.

В Cursor глобальный Override OpenAI Base URL перенаправляет и другие модели на локальный сервер. Это ломает встроенные GPT/Claude/Composer, поэтому BioMistral туда не подключается как постоянная модель.

Для теста из любого OpenAI-совместимого клиента:

- Base URL: `http://127.0.0.1:8080/v1`
- Model: `biomistral-7b-instruct`
- API key: значение из `biomistral-api-key.txt`

## Траблшутинг

| Симптом | Решение |
| --- | --- |
| `401 Invalid API Key` | Передать `Authorization: Bearer <значение biomistral-api-key.txt>`; в Web UI вставить ключ в Settings. |
| `huggingface-cli` не найден | Использовать `python -c "from huggingface_hub import login; login()"`. |
| `The CUDA Toolkit directory '' does not exist` | В текущем окне задать `CudaToolkitDir`, `CUDA_PATH`, `CUDA_PATH_V13_4`, удалить `build`, снова запустить CMake с `-T cuda=...`. |
| `llama-server.exe --version` не выводит текст | Добавить `CUDA\v13.4\bin\x64` в PATH, скопировать три CUDA DLL рядом с exe. |
| Телефон не открывает страницу | Проверить один Wi-Fi, IP, что сервер запущен с `--host 0.0.0.0`, и правило Firewall `LocalSubnet`. |
| CUDA OOM | Вернуть `ctx-size 2048`, закрыть другие GPU-программы. |
| Фактическая ошибка / галлюцинация | Использовать английский, температуру 0.1–0.2, явный контекст и проверять ответ по источникам. |
| Ответ обрезан | Сократить входной текст; у модели нативное окно 2048. |

## Источники

- [BioMistral model card](https://huggingface.co/BioMistral/BioMistral-7B)
- [BioMistral GGUF](https://huggingface.co/BioMistral/BioMistral-7B-GGUF)
- [BioMistral paper](https://arxiv.org/abs/2402.10373)
- [llama.cpp server](https://github.com/ggml-org/llama.cpp/tree/master/tools/server)
