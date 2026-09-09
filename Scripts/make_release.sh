#!/bin/zsh
# 打 release：将应用、所有工具二进制与全部模型打包成一个 DMG
# 输出：release/Mac图片与视频超分-<version>.dmg
set -e
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
ARCH=$(uname -m)
APP_NAME="Mac图片与视频超分"
RELEASE_DIR="release"
STAGE="$RELEASE_DIR/staging"
DMG="$RELEASE_DIR/${APP_NAME}-${VERSION}-${ARCH}.dmg"
BIN_LOCAL="$HOME/Library/Application Support/MacVision/bin"

echo "==> 构建 release 版本"
swift build -c release

echo "==> 打包 .app"
./Scripts/build_app.sh release

rm -rf "$RELEASE_DIR"
mkdir -p "$STAGE"

cp -R "build/MacVision.app" "$STAGE/$APP_NAME.app"

# 复制全部依赖工具与模型（确保 release 自包含、零依赖运行）
if [ -d "$BIN_LOCAL" ]; then
  echo "==> 复制依赖目录（含全部模型）"
  mkdir -p "$STAGE/Tools"
  for item in "$BIN_LOCAL"/*; do
    name=$(basename "$item")
    # 跳过不是工具/模型的旧文件
    case "$name" in
      ffmpeg|ffprobe|realesrgan-ncnn-vulkan|realcugan-ncnn-vulkan|rife-ncnn-vulkan|Anime4KCPP_CLI|models|models-se|models-pro|models-nose|rife|rife-HD|rife-UHD|rife-anime|rife-v2|rife-v2.3|rife-v2.4|rife-v3.0|rife-v3.1|rife-v4|rife-v4.6)
        if [ -d "$item" ]; then
          cp -R "$item" "$STAGE/Tools/"
        else
          cp "$item" "$STAGE/Tools/"
          chmod +x "$STAGE/Tools/$name" 2>/dev/null
        fi
        ;;
    esac
  done
  xattr -dr com.apple.quarantine "$STAGE/Tools" 2>/dev/null || true
fi

# 创建可读文档
cat > "$STAGE/使用说明.txt" <<'TXT'
Mac图片与视频超分 v1.0.0

首次运行：
1. 把本磁盘映像拖到 /Applications 后打开
2. 首次启动若提示「无法打开，因为无法验证开发者」，请到
   「系统设置 → 隐私与安全性」点击「仍要打开」

依赖工具已放在 ~/Library/Application Support/MacVision/bin，
应用启动后会自动检测；如需手动指定路径，可在偏好设置（⌘,）中配置。

详细使用说明见本仓库 README。
TXT

# 创建 Applications 软链接（DMG 美观）
ln -s /Applications "$STAGE/Applications"

# 创建 DMG。CI 上 hdiutil 偶发 "Resource busy"，重试若干次；
# 仍失败则回退为 zip，保证 Release 一定有可用产物。
ZIP="$RELEASE_DIR/${APP_NAME}-${VERSION}-${ARCH}.zip"
echo "==> 创建 DMG"
ok=0
for attempt in 1 2 3; do
  if hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1; then
    ok=1
    break
  fi
  echo "    第 $attempt 次失败，重试…"
  sleep 8
done

if [ "$ok" = "1" ]; then
  echo "==> 完成: $DMG"
  echo "    体积: $(du -h "$DMG" | cut -f1)"
else
  echo "!! DMG 创建失败，回退为 zip 打包"
  rm -f "$DMG"
  (cd "$STAGE" && zip -qry "../$(basename "$ZIP")" .)
  echo "==> 完成: $ZIP"
  echo "    体积: $(du -h "$ZIP" | cut -f1)"
fi

rm -rf "$STAGE"
