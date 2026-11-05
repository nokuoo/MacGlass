#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -x "$ROOT_DIR/Vendor/yabai" ]]; then
    echo "缺少 Vendor/yabai。请先放入可执行的 yabai 7.1.25 二进制。" >&2
    exit 1
fi

echo "==> 运行单元测试"
swift test

echo "==> 编译 Release"
swift build -c release --product MacGlass
BIN_DIR="$(swift build -c release --show-bin-path)"

APP_DIR="$ROOT_DIR/dist/MacGlass.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ -e "$APP_DIR" ]]; then
    /usr/bin/find "$APP_DIR" -depth -delete
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 755 "$BIN_DIR/MacGlass" "$MACOS_DIR/MacGlass"
install -m 644 "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
install -m 755 "$ROOT_DIR/Vendor/yabai" "$RESOURCES_DIR/yabai"
install -m 644 "$ROOT_DIR/Vendor/yabai-LICENSE.txt" "$RESOURCES_DIR/yabai-LICENSE.txt"

echo "==> 签名"
SIGNING_IDENTITY="${MACGLASS_CODESIGN_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" --identifier com.macglass.app "$RESOURCES_DIR/yabai"
# 显式写入标识符要求，避免 ad-hoc 签名只按 CDHash 绑定 TCC 授权。
codesign --force --sign "$SIGNING_IDENTITY" \
    --identifier com.macglass.app \
    --requirements '=designated => identifier "com.macglass.app"' \
    "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo ""
echo "构建完成：$APP_DIR"
echo "启动命令：open \"$APP_DIR\""
echo "安装到应用程序：./scripts/install-app.sh"
echo "环境诊断：\"$MACOS_DIR/MacGlass\" --diagnose"
