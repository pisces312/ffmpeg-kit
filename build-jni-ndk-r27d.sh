#!/bin/bash
set -e

# 用法: ./build-jni-ndk-r27d.sh [--debug]
#   --debug: 编译带符号表的 debug 版本（不 strip，-O0 -g）

DEBUG_MODE=false
if [ "$1" == "--debug" ]; then
    DEBUG_MODE=true
    echo "=========================================="
    echo " DEBUG MODE: 保留符号表，关闭优化"
    echo "=========================================="
fi

export NDK=/home/pisces312/android-ndk-r27d
export BASEDIR=/mnt/d/nili/3rd_party_projects/ffmpeg-kit

# 根据模式选择 Application.mk 配置
APP_MK="$BASEDIR/android/jni/Application.mk"
APP_MK_BACKUP="$APP_MK.backup"

# 备份原文件
cp -f "$APP_MK" "$APP_MK_BACKUP"

if [ "$DEBUG_MODE" == "true" ]; then
    # Debug: 改 APP_OPTIM 为 debug，替换 -O3 为 -O0 -g
    sed -i 's/^APP_OPTIM := release/APP_OPTIM := debug/' "$APP_MK"
    sed -i 's/-O3/-O0 -g/' "$APP_MK"
    echo ">>> Application.mk 已改为 debug 配置"
else
    echo ">>> Application.mk 保持 release 配置"
fi

echo "=========================================="
echo " 1. Building JNI library (ndk-build)"
echo "=========================================="
cd "$BASEDIR/android"
rm -rf obj/local
$NDK/ndk-build \
    NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=jni/Android.mk \
    NDK_APPLICATION_MK=jni/Application.mk \
    APP_ALLOW_MISSING_DEPS=true

echo ">>> JNI build done"

echo "=========================================="
echo " 2. Copying FFmpeg .so files"
echo "=========================================="
FFMPEG_LIBS="$BASEDIR/prebuilt/android-arm64/ffmpeg/lib"
JNI_LIBS="$BASEDIR/android/libs/arm64-v8a"
mkdir -p "$JNI_LIBS"

for so in libavcodec.so libavdevice.so libavfilter.so libavformat.so libavutil.so libswresample.so libswscale.so; do
    if [ -f "$FFMPEG_LIBS/$so" ]; then
        cp -vf "$FFMPEG_LIBS/$so" "$JNI_LIBS/$so"
    else
        echo "WARNING: $so not found in $FFMPEG_LIBS"
    fi
done

if [ -f "$JNI_LIBS/libavcodec.so" ]; then
    echo ">>> libavcodec.so size: $(stat -c%s "$JNI_LIBS/libavcodec.so") bytes"
fi

# 恢复 Application.mk
cp -f "$APP_MK_BACKUP" "$APP_MK"
rm -f "$APP_MK_BACKUP"

echo "=========================================="
echo " JNI build complete!"
echo " SO files location: $JNI_LIBS"
echo "=========================================="
