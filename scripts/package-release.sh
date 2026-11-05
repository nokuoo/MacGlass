#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(date +%Y%m%d)}"
ARCH="${2:-$(uname -m)}"
APP="$ROOT_DIR/dist/MacGlass.app"
STAGE="$ROOT_DIR/dist/release"
ARCHIVE="$STAGE/MacGlass-${VERSION}-${ARCH}-unsigned.zip"
DMG="$STAGE/MacGlass-${VERSION}-${ARCH}-unsigned.dmg"
DMG_STAGE="$STAGE/dmg"

if [[ ! -d "$APP" ]]; then
    echo "未找到 $APP，请先运行 ./scripts/build-app.sh" >&2
    exit 1
fi

mkdir -p "$STAGE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

# 生成可拖拽安装的 DMG：App 与 /Applications 快捷方式并排。
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
ditto "$APP" "$DMG_STAGE/MacGlass.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
    -volname "MacGlass" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null
rm -rf "$DMG_STAGE"

cat > "$STAGE/README.txt" <<EOF
MacGlass ${VERSION}（${ARCH} / 未签名构建）

这是未使用 Developer ID 签名、也未经过 Apple 公证的构建，首次打开会被
Gatekeeper 拦截。确认来源可信后，在“系统设置 → 隐私与安全性”中选择
“仍要打开”，或在终端执行：

  xattr -d com.apple.quarantine /Applications/MacGlass.app

安装：

  ditto -x -k MacGlass-${VERSION}-${ARCH}-unsigned.zip /tmp/macglass
  ditto /tmp/macglass/MacGlass.app /Applications/MacGlass.app
  open /Applications/MacGlass.app

使用前仍需按项目 README 关闭 SIP 的“文件系统保护”和“调试限制”，并授予
MacGlass 辅助功能权限。关闭 SIP 会降低系统安全性，请自行评估风险。
EOF

shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
shasum -a 256 "$DMG" > "$DMG.sha256"

echo "发布包：$ARCHIVE"
echo "安装镜像：$DMG"
echo "校验文件：$ARCHIVE.sha256"
