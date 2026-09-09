#!/bin/zsh
# 将 SwiftPM 构建结果打包为 MacVision.app
set -e
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

APP="build/MacVision.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp ".build/$CONFIG/MacVision" "$CONTENTS/MacOS/MacVision"

# 应用图标
if [ -f "Assets/AppIcon.icns" ]; then
  cp "Assets/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# 本地化资源（菜单栏随系统语言显示中文）
if [ -d "Resources" ]; then
  for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$CONTENTS/Resources/"
  done
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Mac图片与视频超分</string>
    <key>CFBundleDisplayName</key>
    <string>Mac图片与视频超分</string>
    <key>CFBundleIdentifier</key>
    <string>com.macvision.upscaler</string>
    <key>CFBundleExecutable</key>
    <string>MacVision</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>基于开源组件：FFmpeg / Real-ESRGAN / Real-CUGAN / Anime4K / RIFE (ncnn-vulkan)</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh_CN</string>
        <string>zh-Hans</string>
        <string>en</string>
    </array>
</dict>
</plist>
PLIST

# 若仓库根目录存在 bin/，则随应用打包依赖工具
if [ -d "bin" ]; then
  echo "==> 打包 bin/ 到应用资源"
  cp -R bin "$CONTENTS/Resources/bin"
  find "$CONTENTS/Resources/bin" -type f -perm +111 -exec xattr -dr com.apple.quarantine {} \; 2>/dev/null || true
fi

codesign --force --deep --sign - "$APP"
echo "==> 完成: $APP"
echo "    运行: open \"$APP\""
