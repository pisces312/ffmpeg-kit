#!/bin/bash
set -e

# ============================================================
# 轨道 B：FFmpeg CLI 静态可执行文件（ffmpeg / ffprobe）
#
# 用法：
#   ./build-cli-binary-ndk-r27d.sh [full|minimal]     默认 minimal
#     full    : 全量组件（183 编码器 / 521 解码器 / 30 协议），约 15 MB
#     minimal : --disable-everything 后按清单启用，约 8.8 MB
#
# 环境变量：
#   FFMPEG_SRC=<源码目录>     默认 /mnt/d/3rd-party-projects/ffmpeg-8.1.3
#   NDK=<NDK 目录>            默认 /home/pisces312/android-ndk-r27d
#   IN_TREE=1                 原地构建（默认，与历史脚本一致）
#
# ⚠ 重要：本脚本默认原地构建，会先对 $FFMPEG_SRC 执行 make distclean，
#         从而清掉轨道 A（AAR）使用的 config.h。
#         推荐顺序：先跑 AAR（build-ffmpeg-ndk-27d.sh），再跑本脚本。
#         若之后还要重建 AAR，必须重跑 build-ffmpeg-ndk-27d.sh（会重新 configure）。
#
# 为什么不打包进 App：静态可执行文件无法在运行时通过 JNI 拿到 JavaVM，
# 也就拿不到 AMediaCodec —— mediacodec 硬编只有轨道 A（共享库 + JNI）能用。
# 因此本脚本产出仅作调试 / 独立工具用途。
# ============================================================

MODE="${1:-minimal}"
case "$MODE" in
    full|minimal) ;;
    *) echo "用法: $0 [full|minimal]"; exit 1 ;;
esac

# 仓库根目录自动推导（避免历史上写死 /mnt/d/nili/... 的问题）
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[ -d "$BASEDIR/src/ffmpeg" ] || { echo "ERROR: $BASEDIR 不像 ffmpeg-kit 仓库根目录"; exit 1; }

export NDK="${NDK:-/home/pisces312/android-ndk-r27d}"
export FFMPEG_SRC="${FFMPEG_SRC:-/mnt/d/3rd-party-projects/ffmpeg-8.1.3}"

TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64
SYSROOT=$TOOLCHAIN/sysroot
API=24
TARGET=aarch64-linux-android$API

CC=$TOOLCHAIN/bin/${TARGET}-clang
CXX=$TOOLCHAIN/bin/${TARGET}-clang++
STRIP=$TOOLCHAIN/bin/llvm-strip

# 输出目录：不污染 prebuilt/android-arm64/ffmpeg（那是轨道 A 的）
OUT_ROOT="$BASEDIR/out/cli"
if [ "$MODE" = "full" ]; then
    PREFIX="$OUT_ROOT/full"
else
    PREFIX="$OUT_ROOT/minimal"
fi

# ★ 关键修正：pkg-config 必须指向轨道 A 的 prebuilt，否则 --enable-libx264/libx265
#   找不到 arm64 静态库（历史脚本误指向自己的输出目录，等于空目录）
EXT_PREFIX="$BASEDIR/prebuilt/android-arm64/ffmpeg"
export PKG_CONFIG_PATH="$EXT_PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"

[ -f "$FFMPEG_SRC/configure" ] || { echo "ERROR: 找不到 $FFMPEG_SRC/configure"; exit 1; }

echo "=========================================="
echo " Mode:     $MODE"
echo " BASEDIR:  $BASEDIR"
echo " SRC:      $FFMPEG_SRC"
echo " NDK:      $NDK"
echo " PREFIX:   $PREFIX"
echo " EXT libs: $EXT_PREFIX"
echo "=========================================="

mkdir -p "$PREFIX"
cd "$FFMPEG_SRC"

# 原地构建：先清理（含轨道 A 的 config.h）
make distclean 2>/dev/null || true

COMMON_ARGS=(
    --prefix="$PREFIX"
    --target-os=android
    --arch=aarch64
    --cpu=armv8-a
    --cc="$CC"
    --cxx="$CXX"
    --strip="$STRIP"
    --enable-cross-compile
    --sysroot="$SYSROOT"
    --disable-debug
    --enable-static
    --disable-shared
    --enable-small
    --enable-gpl
    --enable-nonfree
    --enable-neon
    --disable-doc
    --disable-ffplay
    --extra-ldflags="-pie -static"
)

if [ "$MODE" = "full" ]; then
    # 全量：不裁剪任何组件，只做静态 + 体积优化
    ./configure "${COMMON_ARGS[@]}" \
        --extra-cflags="-O3 -Wall -fPIE -fPIC"
else
    # 精简：仅 H.264/H.265 软硬编解码 + AAC/MP3 音频
    # 注意：--pkg-config-flags="--static" 让 x264/x265 的 Libs.private(-lm -lc++) 也参与链接
    ./configure "${COMMON_ARGS[@]}" \
        --disable-everything \
        --enable-libx264 \
        --enable-libx265 \
        --enable-encoder=libx264,libx265,h264_v4l2m2m,aac \
        --enable-decoder=h264,hevc,h264_v4l2m2m,hevc_v4l2m2m,aac,aac_latm,mp3,mp3float \
        --enable-muxer=mp4,mov,matroska,avi,flv \
        --enable-demuxer=mp4,mov,matroska,avi,flv \
        --enable-filter=scale,crop,trim,concat,volume,fade,rotate,transpose,overlay,format,fps,afade,acrossfade,aformat,atrim,volumedetect,cropdetect \
        --enable-protocol=file \
        --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc \
        --enable-parser=h264,hevc,aac,mpegaudio \
        --enable-swscale \
        --enable-swresample \
        --enable-avfilter \
        --enable-avformat \
        --enable-avcodec \
        --enable-avutil \
        --extra-cflags="-O3 -Wall -fPIE -fPIC -I$EXT_PREFIX/include" \
        --extra-ldflags="-pie -static -L$EXT_PREFIX/lib" \
        --extra-libs="-lm -lc++" \
        --pkg-config-flags="--static"
fi

echo ">>> configure done, building..."
make -j"$(nproc)"
make install

echo "=========================================="
echo " 构建完成：$PREFIX/bin/"
ls -lh "$PREFIX/bin/" 2>/dev/null || ls -lh "$FFMPEG_SRC/ffmpeg" "$FFMPEG_SRC/ffprobe"
echo "=========================================="
echo " 校验建议："
echo "   $TOOLCHAIN/bin/llvm-readelf -h $PREFIX/bin/ffmpeg | grep Machine   # 应为 AArch64"
echo "   $TOOLCHAIN/bin/llvm-readelf -d $PREFIX/bin/ffmpeg | grep NEEDED    # 应为空（静态）"
echo "=========================================="
