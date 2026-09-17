#!/usr/bin/env bash
# 构建 Hestia.app。
#
#   ./build.sh            仅本机架构，用于日常调试
#   ./build.sh --check    只做类型检查，不产出二进制
#   ./build.sh --dev      换用独立的 bundle 标识，可与已安装的正式版同时运行
#   ./build.sh --dmg      另外打出 DMG 安装包，发版用
#
# 本机只装了 Command Line Tools，SwiftPM 的清单编译不可用，因此直接调 swiftc。
# 27.0 SDK 把 SwiftUI 的 @State 改成了宏，其编译插件只随完整 Xcode 提供，
# 所以固定用 26.5 SDK。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC="$ROOT/mac"
OUT="$MAC/build"
APP=""  # 解析完参数后再定
DEPLOY_TARGET="14.0"

export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
[ -d "$SDKROOT" ] || { echo "找不到 SDK：$SDKROOT" >&2; exit 1; }

MODE="build"
DMG=0
# 调试构建换一个 bundle 标识与应用名，好与已安装的正式版同时运行
BUNDLE_ID="com.kira.hestia"
APP_NAME="Hestia"
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --dmg) DMG=1 ;;
    --dev) BUNDLE_ID="com.kira.hestia.dev"; APP_NAME="Hestia Dev" ;;
    *) echo "未知参数：$arg" >&2; exit 1 ;;
  esac
done

SOURCES=$(find "$MAC/Sources" -name '*.swift' | sort)

swift_build() {
  local arch="$1" output="$2"
  # shellcheck disable=SC2086
  swiftc -O -parse-as-library \
    -target "${arch}-apple-macosx${DEPLOY_TARGET}" \
    -sdk "$SDKROOT" \
    -I "$MAC/Bridge" \
    -L "$3" -lhestia_core \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -o "$output" \
    $SOURCES
}

if [ "$MODE" = "check" ]; then
  # shellcheck disable=SC2086
  swiftc -typecheck -parse-as-library \
    -target "arm64-apple-macosx${DEPLOY_TARGET}" \
    -sdk "$SDKROOT" -I "$MAC/Bridge" $SOURCES
  echo "类型检查通过"
  exit 0
fi

APP="$OUT/$APP_NAME.app"
rm -rf "$OUT"
mkdir -p "$APP/Contents/"{MacOS,Resources,Frameworks}

echo "▸ 构建 Rust 核心"
cargo build --release --manifest-path "$ROOT/core/Cargo.toml"
cp "$ROOT/core/target/release/libhestia_core.dylib" "$APP/Contents/Frameworks/"
# 链接器把被链接库的 install name 原样写进可执行文件，必须先改名再链接包内这一份，
# 否则可执行文件会指向构建目录里的绝对路径
install_name_tool -id "@rpath/libhestia_core.dylib" "$APP/Contents/Frameworks/libhestia_core.dylib"
LIBDIR="$APP/Contents/Frameworks"

echo "▸ 构建 Swift 界面"
swift_build "$(uname -m)" "$APP/Contents/MacOS/$APP_NAME" "$LIBDIR"

echo "▸ 组装 bundle"
VERSION=$(grep -m1 '^version' "$ROOT/core/Cargo.toml" | cut -d'"' -f2)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$DEPLOY_TARGET</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Hestia</string>
</dict>
</plist>
PLIST

cp "$ROOT/mac/Resources/icon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/mac/Resources/tray-idle.png" "$APP/Contents/Resources/"
cp "$ROOT/mac/Resources"/tray-run-*.png "$APP/Contents/Resources/"
cp "$ROOT/mac/Resources/icon.png" "$APP/Contents/Resources/app-icon.png"

codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  （未签名，本机可直接运行）"

echo "完成：$APP"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"

if [ "$DMG" = 1 ]; then
  echo "▸ 打包 DMG"
  # 应用内更新会挂载 DMG、取根目录下的 .app 替换自身；Applications 链接供手动拖拽安装
  STAGE="$OUT/dmg"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/$APP_NAME.app"
  ln -s /Applications "$STAGE/Applications"
  DMG_PATH="$OUT/${APP_NAME// /_}_${VERSION}_$(uname -m).dmg"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$STAGE"
  echo "DMG：$DMG_PATH"
fi
