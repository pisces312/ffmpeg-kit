#!/bin/bash
# check-aar-ffmpeg-version.sh
# 检查 Android AAR 文件中 FFmpeg 的版本号
# 用法: ./check-aar-ffmpeg-version.sh <aar文件路径>

set -e

AAR_PATH="$1"

if [ -z "$AAR_PATH" ]; then
    echo "用法: $0 <aar文件路径>"
    echo "示例: $0 /mnt/d/nili/my-git-projects/StreamClip/app/libs/ffmpeg-kit-full-gpl-arm64v8a-8.0.0.aar"
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
    
    # 方法1: 直接搜索 "FFmpeg version" 字符串
    VERSION_STR=$(strings "$SO_FILE" 2>/dev/null | grep -i "ffmpeg version" | head -1 || true)
    if [ -n "$VERSION_STR" ]; then
        echo "版本字符串: $VERSION_STR"
    fi
    
    # 方法2: 通过 libavutil SONAME 推断
    SONAME=$(strings "$SO_FILE" 2>/dev/null | grep "^LIBAVUTIL_[0-9]" | head -1 || true)
    if [ -n "$SONAME" ]; then
        echo "libavutil SONAME: $SONAME"
        
        # 根据 SONAME 推断 FFmpeg 版本（近似）
        case "$SONAME" in
            LIBAVUTIL_56) echo "推断 FFmpeg 版本: ~4.4.x" ;;
            LIBAVUTIL_57) echo "推断 FFmpeg 版本: ~5.0.x" ;;
            LIBAVUTIL_58) echo "推断 FFmpeg 版本: ~5.1.x / 6.0" ;;
            LIBAVUTIL_59) echo "推断 FFmpeg 版本: ~6.0.x / 6.1" ;;
            LIBAVUTIL_60) echo "推断 FFmpeg 版本: ~7.0.x / 7.1 / n8.0" ;;
            LIBAVUTIL_61) echo "推断 FFmpeg 版本: ~7.1.x / n8.0+" ;;
            *) echo "推断 FFmpeg 版本: 未知 ($SONAME)" ;;
        esac
    fi
    
    # 方法3: 搜索 n7.0, n8.0 等开发分支标记
    DEV_BRANCH=$(strings "$SO_FILE" 2>/dev/null | grep -oE "n[0-9]+\.[0-9]+" | head -1 || true)
    if [ -n "$DEV_BRANCH" ]; then
        echo "开发分支标记: $DEV_BRANCH"
    fi
    
    # 方法4: 搜索 git commit hash（如果有）
    GIT_HASH=$(strings "$SO_FILE" 2>/dev/null | grep -oE "[0-9a-f]{40}" | head -1 || true)
    if [ -n "$GIT_HASH" ]; then
        echo "Git commit: $GIT_HASH"
    fi
    
    echo ""
done

echo "=== 检查完成 ==="
