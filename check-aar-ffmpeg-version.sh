#!/bin/bash
# check-aar-ffmpeg-version.sh
# 检查 Android AAR 文件中 FFmpeg 的版本号
# 用法: ./check-aar-ffmpeg-version.sh <aar文件路径>

set -e

AAR_PATH="$1"

if [ -z "$AAR_PATH" ]; then
    echo "用法: $0 <aar文件路径>"
    echo "示例: $0 /mnt/d/my-projects/StreamClip/app/libs/ffmpeg-kit-8.1.3.aar"
    exit 1
fi

if [ ! -f "$AAR_PATH" ]; then
    echo "错误: 文件不存在: $AAR_PATH"
    exit 1
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== 检查 AAR: $(basename "$AAR_PATH") ==="
echo ""

# 解压 AAR
cd "$TMPDIR"
unzip -q "$AAR_PATH" 2>/dev/null || {
    echo "错误: 无法解压 AAR 文件"
    exit 1
}

# 检查是否有 jni 目录
if [ ! -d "jni" ]; then
    echo "错误: AAR 中未找到 jni/ 目录"
    exit 1
fi

# 列出所有 ABI
ABIS=$(find jni -name "libavutil.so" -exec dirname {} \; | sed 's|jni/||' | sort)

if [ -z "$ABIS" ]; then
    echo "错误: 未找到 libavutil.so，可能不是 ffmpeg-kit AAR"
    exit 1
fi

echo "找到的 ABI:"
for abi in $ABIS; do
    echo "  - $abi"
done
echo ""

# 检查每个 ABI 的 FFmpeg 版本
for abi in $ABIS; do
    SO_FILE="jni/$abi/libavutil.so"
    
    if [ ! -f "$SO_FILE" ]; then
        echo "[$abi] 未找到 libavutil.so"
        continue
    fi
    
    echo "--- [$abi] ---"

    # libavutil 的 SONAME（符号版本节点）决定 FFmpeg 大版本，见下方对照表
    SONAME=$(strings "$SO_FILE" 2>/dev/null | grep -E "^LIBAVUTIL_[0-9]+$" | head -1 || true)
    FFMAJOR=""
    if [ -n "$SONAME" ]; then
        echo "libavutil SONAME: $SONAME"
        case "$SONAME" in
            LIBAVUTIL_56) FFMAJOR=4; echo "推断 FFmpeg 大版本: 4.x" ;;
            LIBAVUTIL_57) FFMAJOR=5; echo "推断 FFmpeg 大版本: 5.x" ;;
            LIBAVUTIL_58) FFMAJOR=6; echo "推断 FFmpeg 大版本: 6.x" ;;
            LIBAVUTIL_59) FFMAJOR=7; echo "推断 FFmpeg 大版本: 7.x" ;;
            LIBAVUTIL_60) FFMAJOR=8; echo "推断 FFmpeg 大版本: 8.x" ;;
            LIBAVUTIL_61) FFMAJOR=9; echo "推断 FFmpeg 大版本: 9.x" ;;
            *) echo "推断 FFmpeg 大版本: 未知 ($SONAME)" ;;
        esac
    fi

    # 精确版本：av_version_info() 内嵌的是 FFMPEG_VERSION 宏的字面量（如 "8.1" / "8.1.3"）。
    # 注意 strings 默认最小长度是 4，"8.1" 这种 3 字符会被漏掉 → 用 -n 3。
    # 库里同时存在大量无关版本串（7.1.4 / 9.1.4 等来自其他组件），
    # 因此用上一步得到的大版本号过滤，并在多个候选中取**最长**的（8.1.3 优先于 8.1）。
    if [ -n "$FFMAJOR" ]; then
        EXACT=$(strings -n 3 "$SO_FILE" 2>/dev/null \
                | grep -E "^${FFMAJOR}\.[0-9]+(\.[0-9]+)?$" \
                | sort -u \
                | awk '{ print length, $0 }' | sort -rn | head -1 | cut -d' ' -f2- || true)
        if [ -n "$EXACT" ]; then
            echo "FFmpeg 版本: $EXACT"
        else
            echo "FFmpeg 版本: 未取到字面量（大版本 ${FFMAJOR}.x）"
        fi
    else
        # 兜底：只报所有形似版本的字面量，供人工判断
        echo "候选版本串: $(strings "$SO_FILE" 2>/dev/null | grep -E "^[0-9]+\.[0-9]+(\.[0-9]+)?$" | sort -u | head -5 | tr '\n' ' ')"
    fi

    # 构建配置（确认 mediacodec / 外部库是否真的编进去了）
    CONF=$(strings "$SO_FILE" 2>/dev/null \
           | grep -oE "enable-(mediacodec|libx264|libx265|libmp3lame|gpl|nonfree)" \
           | sort -u | tr '\n' ' ' || true)
    [ -n "$CONF" ] && echo "构建开关: $CONF"

    echo ""
done

echo "=== 检查完成 ==="
