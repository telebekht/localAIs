#!/usr/bin/env bash
# BioMistral-7B-Instruct Q4_K_M for the checklist machine:
# i5-11500, 32 GB RAM, RTX 3060 Ti 8 GB, Windows 11.
# Launch from PowerShell, not with curl -fsSL (curl there is Invoke-WebRequest):
# Invoke-WebRequest -Uri "https://raw.githubusercontent.com/telebekht/localAIs/cursor/biomistral-install-964a/scripts/install-biomistral.sh" -OutFile "$env:USERPROFILE\install-biomistral.sh"; & "C:\Program Files\Git\bin\bash.exe" "$env:USERPROFILE\install-biomistral.sh"
# Research use only. Not for clinical decisions.
set -euo pipefail

PORT=8080
THREADS=10
QUANT="Q4_K_M"
MODEL_REPO="BioMistral/BioMistral-7B-GGUF"
MODEL_FILE="ggml-model-Q4_K_M.gguf"

die() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Не найдено: $1"; }

ask() {
  local prompt="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer
    printf '%s' "${answer:-$default}"
  else
    read -r -p "$prompt: " answer
    printf '%s' "$answer"
  fi
}

to_unix() {
  local p="${1//\\//}"
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$p"; else printf '%s' "$p"; fi
}

to_win() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *) die "Этот установщик для Git Bash на Windows. Скриншот системы — Windows 11." ;;
esac

need curl
need powershell.exe
command -v unzip >/dev/null 2>&1 || command -v tar >/dev/null 2>&1 || die "Нужен unzip или tar."

cat <<'EOF'
BioMistral-7B-Instruct Q4_K_M — только для исследований.
Модель не проходила клиническую валидацию. Не используйте её для
диагностики, лечения или решений о здоровье.
EOF
confirm="$(ask "Продолжить? y/N" "N")"
[[ "$confirm" =~ ^[Yy]$ ]] || die "Отменено."

root_raw="$(ask "Каталог установки" "D:/AI")"
[[ -n "$root_raw" ]] || die "Путь пустой."
ROOT="$(to_unix "$root_raw")"
mkdir -p "$ROOT"

ctx="$(ask "Контекст, токенов (2048 надёжно на 8 GB, 4096 осторожно)" "2048")"
[[ "$ctx" =~ ^[0-9]+$ ]] || die "Контекст должен быть числом."
(( ctx >= 512 && ctx <= 4096 )) || die "Для BioMistral на 8 GB оставьте контекст от 512 до 4096."

lan="$(ask "Открыть веб-интерфейс в домашней сети? y/N" "N")"
if [[ "$lan" =~ ^[Yy]$ ]]; then HOST_BIND="0.0.0.0"; else HOST_BIND="127.0.0.1"; fi

BIN_DIR="$ROOT/llama.cpp/bin"
MODEL_DIR="$ROOT/models/BioMistral/BioMistral-7B-GGUF"
SCRIPTS="$ROOT/scripts"
mkdir -p "$BIN_DIR" "$MODEL_DIR" "$SCRIPTS"
WIN_ROOT="$(to_win "$ROOT")"
WIN_BIN="$(to_win "$BIN_DIR")"
WIN_SCRIPTS="$(to_win "$SCRIPTS")"

echo
echo "Проверка видеокарты..."
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || true
  DRIVER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1 | tr -d ' ')"
  DRIVER_MAJOR="${DRIVER%%.*}"
else
  DRIVER=""
  DRIVER_MAJOR=0
  echo "nvidia-smi не найден. Поставьте драйвер RTX 3060 Ti и повторите, если сервер не увидит GPU."
fi
if [[ "$DRIVER_MAJOR" =~ ^[0-9]+$ && "$DRIVER_MAJOR" -ge 580 ]]; then
  CUDA_TAG="13.5"
else
  CUDA_TAG="12.4"
fi
echo "Будет скачан llama.cpp Windows CUDA $CUDA_TAG."

download() {
  local url="$1" dest="$2"
  if [[ -f "$dest" ]]; then
    echo "Уже есть: $dest"
    return
  fi
  echo "Скачивание: $url"
  curl -fL --retry 3 --retry-delay 2 -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

extract_zip() {
  local zip="$1" dest="$2"
  mkdir -p "$dest"
  if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "$zip" -d "$dest"
  else
    tar -xf "$zip" -C "$dest"
  fi
}

echo
echo "Поиск последнего Windows CUDA $CUDA_TAG..."
RELEASE_JSON="$(mktemp)"
curl -fsSL "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=5" -o "$RELEASE_JSON"
BIN_URL="$(grep -oE "https://github.com/ggml-org/llama.cpp/releases/download/[^\"[:space:]]+/llama-[^\"[:space:]]+-bin-win-cuda-${CUDA_TAG}-x64.zip" "$RELEASE_JSON" | head -n 1)"
RT_URL="$(grep -oE "https://github.com/ggml-org/llama.cpp/releases/download/[^\"[:space:]]+/cudart-llama-bin-win-cuda-${CUDA_TAG}-x64.zip" "$RELEASE_JSON" | head -n 1)"
rm -f "$RELEASE_JSON"
[[ -n "$BIN_URL" && -n "$RT_URL" ]] || die "Не найден релиз llama.cpp с CUDA $CUDA_TAG."

BIN_ZIP="$BIN_DIR/llama-cuda.zip"
RT_ZIP="$BIN_DIR/cudart-cuda.zip"
download "$BIN_URL" "$BIN_ZIP"
download "$RT_URL" "$RT_ZIP"
extract_zip "$BIN_ZIP" "$BIN_DIR"
extract_zip "$RT_ZIP" "$BIN_DIR"
SERVER_FOUND="$(find "$BIN_DIR" -type f -name llama-server.exe | head -n 1)"
[[ -n "$SERVER_FOUND" ]] || die "В архиве нет llama-server.exe."
if [[ "$SERVER_FOUND" != "$BIN_DIR/llama-server.exe" ]]; then
  cp -f "$(dirname "$SERVER_FOUND")"/*.exe "$BIN_DIR/" 2>/dev/null || true
  cp -f "$(dirname "$SERVER_FOUND")"/*.dll "$BIN_DIR/" 2>/dev/null || true
fi
find "$BIN_DIR" -type f -name '*.dll' -exec cp -f {} "$BIN_DIR/" \;
[[ -f "$BIN_DIR/llama-server.exe" ]] || die "Не удалось положить llama-server.exe в $BIN_DIR."

echo
echo "Скачивание BioMistral $QUANT (~4.4 GB)..."
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
download "https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}" "$MODEL_PATH"

KEY_FILE="$SCRIPTS/biomistral-api-key.txt"
if [[ ! -f "$KEY_FILE" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$(openssl rand -hex 32)" > "$KEY_FILE"
  else
    MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -Command "\$rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider; \$bytes = New-Object byte[] 32; \$rng.GetBytes(\$bytes); \$text = -join (\$bytes | ForEach-Object { \$_.ToString('x2') }); [System.IO.File]::WriteAllText('$(to_win "$KEY_FILE")', \$text)"
  fi
fi

WIN_MODEL="$(to_win "$MODEL_PATH")"
WIN_KEY="$(to_win "$KEY_FILE")"
WIN_SERVER="$(to_win "$BIN_DIR/llama-server.exe")"

cat > "$SCRIPTS/Start-BioMistral.ps1" <<EOF
\$ErrorActionPreference = "Stop"
\$env:Path = "$WIN_BIN;" + \$env:Path
Write-Host "MODEL: $WIN_MODEL"
Write-Host "PORT: $PORT"
Write-Host "CTX: $ctx"
& "$WIN_SERVER" --model "$WIN_MODEL" --host $HOST_BIND --port $PORT --api-key-file "$WIN_KEY" --alias biomistral-7b-instruct --ctx-size $ctx --n-gpu-layers 99 --parallel 1 --threads $THREADS --temp 0.2 --top-p 0.9 --top-k 40 --min-p 0.05 --repeat-penalty 1.1
EOF

powershell.exe -NoProfile -Command "
\$w = New-Object -ComObject WScript.Shell
\$lnk = \$w.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'BioMistral.lnk'))
\$lnk.TargetPath = 'powershell.exe'
\$lnk.Arguments = '-NoExit -ExecutionPolicy Bypass -File \"$WIN_SCRIPTS\\Start-BioMistral.ps1\"'
\$lnk.WorkingDirectory = '$WIN_ROOT'
\$lnk.Save()
"

if [[ "$HOST_BIND" == "0.0.0.0" ]]; then
  echo "Правило брандмауэра для порта $PORT (нужны права администратора)..."
  powershell.exe -NoProfile -Command "New-NetFirewallRule -DisplayName 'BioMistral $PORT LAN' -Direction Inbound -Protocol TCP -LocalPort $PORT -RemoteAddress LocalSubnet -Action Allow" || echo "Не удалось создать правило. Запустите Git Bash от администратора и повторите установку, либо откройте порт $PORT вручную только для локальной сети."
fi

echo
echo "Готово."
echo "Сервер: $WIN_SERVER"
echo "Модель: $WIN_MODEL"
echo "Ключ:   $WIN_KEY"
echo "Ярлык:  рабочий стол, BioMistral"
echo "Порт:   $PORT, адрес прослушивания $HOST_BIND, контекст $ctx"
echo "Веб:    http://127.0.0.1:$PORT  (ключ вставить в Settings)"
echo "Исследовательское использование. Не для медицинских решений."
