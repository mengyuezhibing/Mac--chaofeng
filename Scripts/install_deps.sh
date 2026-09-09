#!/bin/zsh
set -e

BIN_DIR="$HOME/Library/Application Support/MacVision/bin"
ARCH=$(uname -m)
case "$ARCH" in
  arm64) ARCH_TAG="arm64" ;;
  *)     ARCH_TAG="x86_64" ;;
esac

GH_WEB="https://github.com"
GH_API="https://api.github.com"
if ! curl -fsI --max-time 10 "$GH_API" >/dev/null 2>&1; then
  echo "==> 直连 GitHub 不通，改用 gh-proxy 镜像"
  GH_WEB="https://gh-proxy.com/https://github.com"
  GH_API="https://gh-proxy.com/https://api.github.com"
fi
gh_url() {
  if [ "$GH_WEB" = "https://github.com" ]; then echo "$1"
  else echo "$1" | sed "s|https://github.com|$GH_WEB|"; fi
}

echo "==> 目标目录: $BIN_DIR (架构: $ARCH_TAG)"
mkdir -p "$BIN_DIR"

# ---------- 1. FFmpeg / FFprobe ----------
install_ffmpeg() {
  if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
    echo "==> 已检测到 ffmpeg / ffprobe，跳过"
    return 0
  fi
  # 优先 Homebrew
  if command -v brew >/dev/null 2>&1; then
    echo "==> 使用 Homebrew 安装 ffmpeg"
    brew install ffmpeg 2>/dev/null || true
  fi
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "==> 下载 ffmpeg 静态构建（arm64）"
    curl -fL --retry 3 --max-time 600 \
      "$(gh_url "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-arm64.gz")" \
      -o /tmp/ffmpeg.gz && gunzip -f /tmp/ffmpeg.gz && mv /tmp/ffmpeg "$BIN_DIR/ffmpeg" \
      && chmod +x "$BIN_DIR/ffmpeg" || echo "!! ffmpeg 下载失败"
  fi
  if ! command -v ffprobe >/dev/null 2>&1 && [ ! -x "$BIN_DIR/ffprobe" ]; then
    echo "==> ffprobe 未就绪，尝试 Homebrew"
    command -v brew >/dev/null 2>&1 && brew install ffmpeg 2>/dev/null || true
    if command -v ffprobe >/dev/null 2>&1; then
      cp "$(command -v ffprobe)" "$BIN_DIR/ffprobe" && chmod +x "$BIN_DIR/ffprobe"
    fi
  fi
  if [ ! -x "$BIN_DIR/ffmpeg" ] && command -v ffmpeg >/dev/null 2>&1; then
    cp "$(command -v ffmpeg)" "$BIN_DIR/ffmpeg" && chmod +x "$BIN_DIR/ffmpeg"
  fi
  echo "==> ffmpeg: $([ -x "$BIN_DIR/ffmpeg" ] && echo 就绪 || echo 缺失) / ffprobe: $([ -x "$BIN_DIR/ffprobe" ] && echo 就绪 || echo 缺失)"
}
install_ffmpeg

# ---------- 2. 从 GitHub Releases 下载 ncnn 工具 ----------
fetch_latest_asset() {
  # $1=repo  $2=匹配模式(egrep 正则)
  local repo="$1" pattern="$2"
  local json
  json=$(curl -fsSL "$GH_API/repos/$repo/releases/latest" 2>/dev/null) || return 1
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
  url=$(gh_url "$(fetch_latest_asset "$repo" "$pattern")")
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
  # 复制模型目录：压缩包中除可执行文件外的所有子目录都视为模型
  # （rife 的模型目录名为 rife / rife-v4.6 等，不能用 models* 过滤，否则会漏掉）
  local model_root
  model_root=$(dirname "$bin")
  find "$model_root" -maxdepth 1 -mindepth 1 -type d | while read -r d; do
    local nm; nm=$(basename "$d")
    [ -d "$BIN_DIR/$nm" ] || { cp -R "$d" "$BIN_DIR/" && echo "    模型目录: $nm"; }
  done
  # 部分发布包把模型放在上层目录，一并检查
  find "$(dirname "$model_root")" -maxdepth 1 -mindepth 1 -type d \( -iname 'models*' -o -iname 'rife*' \) 2>/dev/null | while read -r d; do
    local nm; nm=$(basename "$d")
    [ -d "$BIN_DIR/$nm" ] || { cp -R "$d" "$BIN_DIR/" && echo "    模型目录: $nm"; }
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
  json=$(curl -fsSL "$GH_API/repos/upscayl/upscayl-ncnn/releases/latest" 2>/dev/null) || return 1
  url=$(gh_url "$(echo "$json" | tr ',' '\n' | grep '"browser_download_url"' \
        | sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
        | grep -i 'macos' | head -n 1)")
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

  # 自动下载 Real-ESRGAN 官方模型目录（upscayl-bin 与官方模型格式完全一致，可直接复用）
  if [ ! -d "$BIN_DIR/models" ]; then
    echo "==> 下载 Real-ESRGAN 官方模型目录"
    local mtmp murl mdir
    mtmp=$(mktemp -d)
    murl="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip"
    if curl -fL --retry 3 --max-time 900 "$(gh_url "$murl")" -o "$mtmp/m.zip"; then
      ditto -x -k "$mtmp/m.zip" "$mtmp/x"
      mdir=$(find "$mtmp/x" -maxdepth 3 -type d -name models | head -n 1)
      if [ -n "$mdir" ]; then
        cp -R "$mdir" "$BIN_DIR/models" && echo "    已安装 models 目录"
      else
        echo "!! 压缩包中未找到 models 目录"
      fi
    else
      echo "!! 模型目录下载失败"
    fi
    rm -rf "$mtmp"
  else
    echo "==> models 目录已存在，跳过"
  fi
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
  git clone --depth 1 "$GH_WEB/TianZerL/Anime4KCPP.git" "$tmp/src" 2>/dev/null
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
echo "重新打开 Mac图片与视频超分，即可在「环境检测」页确认工具状态。"
