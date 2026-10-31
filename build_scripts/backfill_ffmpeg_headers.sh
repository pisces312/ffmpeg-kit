#!/bin/bash
set -e

# ============================================================
# 回填 FFmpeg 内部头文件到 prebuilt 的 include 目录
#
# 背景：FFmpeg 的 `make install` 只安装**公开**头文件，而 JNI 移植层
# （fftools_* / ffmpegkit.c）依赖 config.h、libavutil/thread.h 等内部头。
# 不回填就会在 ndk-build 阶段报 "No such file or directory"。
#
# 已踩两次：2026-05-13、2026-08。
#
# ★ 同时修正一个历史隐患：旧流程下 include/config.h 内嵌的是"精简版二进制"
#   的 configure 行（含 --disable-everything），与同目录 .so（AAR 全量配置）
#   不同源，导致 JNI 编译时 CONFIG_* 全部按错误值走。
#   本脚本用**构建树的 config.h** 覆盖，并在末尾断言同源。
#
# 用法：./build_scripts/backfill_ffmpeg_headers.sh [源码目录]
# ============================================================

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SRC="${1:-${FFMPEG_SRC:-/mnt/d/3rd-party-projects/ffmpeg-8.1.3}}"
DST="$BASEDIR/prebuilt/android-arm64/ffmpeg/include"

[ -f "$SRC/config.h" ] || { echo "ERROR: $SRC/config.h 不存在（源码未 configure？）"; exit 1; }
[ -f "$SRC/libavutil/ffversion.h" ] || { echo "ERROR: $SRC/libavutil/ffversion.h 不存在"; exit 1; }

echo "=========================================="
echo " SRC: $SRC"
echo " DST: $DST"
echo "=========================================="

mkdir -p "$DST"/libavutil/x86 "$DST"/libavutil/arm "$DST"/libavutil/aarch64 \
         "$DST"/libavcodec/x86 "$DST"/libavcodec/arm

# 20 个内部头文件（清单源自 scripts/android/ffmpeg.sh:513-536）
FILES=(
    config.h
    libavcodec/mathops.h
    libavcodec/x86/mathops.h
    libavcodec/arm/mathops.h
    libavformat/network.h
    libavformat/os_support.h
    libavformat/url.h
    libavutil/attributes_internal.h
    libavutil/bprint.h
    libavutil/getenv_utf8.h
    libavutil/internal.h
    libavutil/libm.h
    libavutil/reverse.h
    libavutil/thread.h
    libavutil/timer.h
    libavutil/x86/asm.h
    libavutil/x86/timer.h
    libavutil/arm/timer.h
    libavutil/aarch64/timer.h
    libavutil/x86/emms.h
)

n=0
for f in "${FILES[@]}"; do
    if [ -f "$SRC/$f" ]; then
        cp -f "$SRC/$f" "$DST/$f"
        n=$((n + 1))
    else
        echo "WARNING: 上游缺少 $f（可能是版本差异，跳过）"
    fi
done
echo ">>> 已回填 $n 个内部头文件"

echo "=========================================="
echo " 同源断言"
echo "=========================================="
fail=0

# 1) config.h 必须是 AAR 全量配置，不是精简版
mc=$(grep -c 'mediacodec' "$DST/config.h" || true)
de=$(grep -c 'disable-everything' "$DST/config.h" || true)
printf "  config.h 含 mediacodec        : %s (期望 1)\n" "$mc"
printf "  config.h 含 disable-everything: %s (期望 0)\n" "$de"
[ "$mc" -ge 1 ] || { echo "  ✗ config.h 不含 mediacodec"; fail=1; }
[ "$de" -eq 0 ] || { echo "  ✗ config.h 是精简版配置"; fail=1; }

# 2) config.h 与构建树完全一致
if cmp -s "$SRC/config.h" "$DST/config.h"; then
    echo "  config.h 与构建树一致         : yes"
else
    echo "  ✗ config.h 与构建树不一致"; fail=1
fi

# 3) 版本号
ver=$(grep -oE '"[0-9]+\.[0-9]+(\.[0-9]+)?"' "$DST/libavutil/ffversion.h" | head -1 | tr -d '"')
printf "  ffversion.h 版本              : %s\n" "$ver"

# 4) 关键文件存在
for f in libavutil/thread.h libavutil/internal.h libavformat/network.h libavcodec/mathops.h; do
    if [ -f "$DST/$f" ]; then echo "  ✓ $f"; else echo "  ✗ 缺少 $f"; fail=1; fi
done

echo "=========================================="
if [ "$fail" -ne 0 ]; then
    echo " 回填校验失败"
    exit 1
fi
echo " 回填完成（$n 个文件），校验通过"
echo "=========================================="
