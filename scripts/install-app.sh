#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="$ROOT_DIR/dist/MacGlass.app"
APP_DEST="/Applications/MacGlass.app"

if [[ ! -d "$APP_SOURCE" ]]; then
    echo "未找到 $APP_SOURCE，请先运行 ./scripts/build-app.sh" >&2
    exit 1
fi

# 正在运行的旧版本必须先退出，否则会把旧进程留在内存里。
osascript -e 'tell application "MacGlass" to quit' >/dev/null 2>&1 || true
sleep 2

if [[ -e "$APP_DEST" ]]; then
    /usr/bin/find "$APP_DEST" -depth -delete
fi

ditto "$APP_SOURCE" "$APP_DEST"
codesign --verify --deep --strict "$APP_DEST"

echo "已安装：$APP_DEST"
echo "启动：open \"$APP_DEST\""
