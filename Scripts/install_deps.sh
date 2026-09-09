#!/bin/zsh
# SnowLeopard Vision for Mac — 依赖安装脚本
# 功能：
#   1. 检测/安装 Homebrew 与 FFmpeg（可选）
#   2. 自动从 GitHub Releases 下载 macOS 版 ncnn 超分/补帧工具
#      并安装到 ~/Library/Application Support/SnowLeopardVision/bin
set -e

BIN_DIR="$HOME/Library/Application Support/SnowLeopardVision/bin"
ARCH=$(uname -m)
case "$ARCH" in
  arm64) ARCH_TAG="arm64" ;;
  *)     ARCH_TAG="x86_64" ;;
esac

echo "==> 目标目录: $BIN_DIR (架构: $ARCH_TAG)"
mkdir -p "$BIN_DIR"

# ---------- 1. Homebrew / FFmpeg ----------
if command -v ffmpeg >/dev/null 2>&1; then
  echo "==> 已检测到 ffmpeg，跳过"
else
  echo "==> 未检测到 ffmpeg"
  if command -v brew >/dev/null 2>&1; then
    echo "==> 使用 Homebrew 安装 ffmpeg"
    brew install ffmpeg
  else
    echo "!! 未安装 Homebrew。可执行以下命令安装后重试："
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo "   brew install ffmpeg"
  fi
fi

# ---------- 2. 从 GitHub Releases 下载 ncnn 工具 ----------
fetch_latest_asset() {
  # $1=repo  $2=匹配模式(egrep 正则)
  local repo="$1" pattern="$2"
  local json
  json=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null) || return 1
  echo "$json" | tr ',' '\n' \
    | grep '"browser_download_url"' \
    | sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
    | grep -iE "$pattern" | head -n 1
}

download_and_install() {
  local name="$1" repo="$2" pattern="$3"
  if [ -x "$BIN_DIR/$name" ] || [ -x "$BIN_DIR/Anime4KCPP_CLI" ]; then
    echo "==> $name 已存在，跳过（如需重装请先删除）"
    return 0
  fi
  echo "==> 查找 $name ($repo)"
  local url
  url=$(fetch_latest_asset "$repo" "$pattern")
  if [ -z "$url" ]; then
    echo "!! 未找到匹配 macOS($ARCH_TAG) 的资源，请手动下载："
    echo "   https://github.com/$repo/releases"
    return 1
  fi
  echo "==> 下载 $url"
  local tmp; tmp=$(mktemp -d)
  curl -fL "$url" -o "$tmp/pkg.zip"
  case "$url" in
    *.tar.gz|*.tgz) tar -xzf "$tmp/pkg.zip" -C "$tmp" ;;
    *)              ditto -x -k "$tmp/pkg.zip" "$tmp/extract" 2>/dev/null || unzip -o "$tmp/pkg.zip" -d "$tmp/extract" ;;
  esac
  # 找到可执行文件（可能位于压缩包子目录中）
  local bin
  bin=$(find "$tmp" -type f -name "$name" -perm +111 | head -n 1)
  if [ -z "$bin" ]; then
    bin=$(find "$tmp" -type f -name "$name" | head -n 1)
  fi
  if [ -z "$bin" ]; then
    echo "!! 压缩包中未找到 $name"
    rm -rf "$tmp"
    return 1
  fi
  cp "$bin" "$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
  # 复制模型目录
  find "$(dirname "$bin")" -maxdepth 1 -type d \( -iname 'models*' -o -iname '*.param' \) | while read -r d; do
    dst="$BIN_DIR/$(basename "$d")"
    [ -d "$dst" ] || cp -R "$d" "$dst"
  done
  # 去除隔离属性，避免 Gatekeeper 拦截
  xattr -dr com.apple.quarantine "$BIN_DIR/$name" 2>/dev/null || true
  rm -rf "$tmp"
  echo "==> 已安装 $name"
}

echo ""
echo "================ 安装 ncnn 工具 ================"
# Real-ESRGAN：官方 20220424 macOS 构建在 Apple Silicon（M 系列）上会段错误，
# 其原因是旧版 ncnn 运行时与新版 macOS 的 MoltenVK 不兼容。
# 这里改用 Upscayl 维护的 upscayl-ncnn 构建（基于新 ncnn，兼容 Apple Silicon，
# 且模型文件格式与官方一致，可直接复用 models/ 目录）。
install_realesrgan_upscayl() {
  local name="realesrgan-ncnn-vulkan"
  if [ -x "$BIN_DIR/$name" ]; then
    echo "==> $name 已存在，跳过"
    return 0
  fi
  echo "==> 查找 upscayl-bin ($BIN_DIR 目标: $name)"
  local json url tmp bin
  json=$(curl -fsSL "https://gh-proxy.com/https://api.github.com/repos/upscayl/upscayl-ncnn/releases/latest" 2>/dev/null) || return 1
  url=$(echo "$json" | tr ',' '\n' | grep '"browser_download_url"' \
        | sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
        | grep -i 'macos' | head -n 1)
  [ -z "$url" ] && { echo "!! 未找到 upscayl-bin macOS 资源"; return 1; }
  echo "==> 下载 $url"
  tmp=$(mktemp -d)
  curl -fL "$url" -o "$tmp/pkg.zip" && ditto -x -k "$tmp/pkg.zip" "$tmp/x"
  bin=$(find "$tmp/x" -type f -name "upscayl-bin" | head -n 1)
  if [ -z "$bin" ]; then echo "!! 未找到 upscayl-bin"; rm -rf "$tmp"; return 1; fi
  cp "$bin" "$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
  xattr -dr com.apple.quarantine "$BIN_DIR/$name" 2>/dev/null || true
  rm -rf "$tmp"
  echo "==> 已安装 $name（upscayl-ncnn 构建）"
  echo "   注意：还需 models/ 模型目录，可从官方"
  echo "   https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip"
  echo "   解压获取（只需其中的 models 目录）"
}
install_realesrgan_upscayl
download_and_install "realcugan-ncnn-vulkan"   "nihui/realcugan-ncnn-vulkan" "realcugan-ncnn-vulkan.*mac(os)?"
download_and_install "rife-ncnn-vulkan"        "nihui/rife-ncnn-vulkan"      "rife-ncnn-vulkan.*mac(os)?"

# Anime4KCPP 没有官方 macOS 预编译版，从源码构建（依赖 cmake + OpenCL 框架）
install_anime4kcpp_from_source() {
  local name="Anime4KCPP_CLI"
  if [ -x "$BIN_DIR/$name" ]; then
    echo "==> $name 已存在，跳过"
    return 0
  fi
  if ! command -v cmake >/dev/null 2>&1; then
    echo "!! 缺少 cmake，无法构建 Anime4KCPP_CLI（可执行：brew install cmake）"
    return 1
  fi
  local tmp=$(mktemp -d)
  echo "==> 克隆 TianZerL/Anime4KCPP"
  git clone --depth 1 https://gh-proxy.com/https://github.com/TianZerL/Anime4KCPP.git "$tmp/src" 2>/dev/null
  cmake -S "$tmp/src" -B "$tmp/build" -DAC_BUILD_CLI=ON -DAC_BUILD_GUI=OFF -DAC_BUILD_VIDEO=OFF -DAC_CORE_WITH_OPENCL=ON -DAC_BUILD_TESTS=OFF -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" >/dev/null
  cmake --build "$tmp/build" -j "$(sysctl -n hw.ncpu)" >/dev/null 2>&1
  if [ ! -x "$tmp/build/bin/ac_cli" ]; then
    echo "!! Anime4KCPP 构建失败"
    rm -rf "$tmp"
    return 1
  fi
  cp "$tmp/build/bin/ac_cli" "$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
  xattr -dr com.apple.quarantine "$BIN_DIR/$name" 2>/dev/null || true
  rm -rf "$tmp"
  echo "==> 已从源码构建并安装 $name"
}
install_anime4kcpp_from_source

echo ""
echo "================ 完成 ================"
echo "已安装到 $BIN_DIR："
ls -la "$BIN_DIR" || true
echo ""
echo "重新打开 SnowLeopard Vision，即可在「环境检测」页确认工具状态。"
