#!/bin/bash
set -e

# 用法: ./build-aar-ndk-r27d.sh [--debug]
#   --debug: 跳过 strip 步骤，保留符号表

DEBUG_MODE=false
if [ "$1" == "--debug" ]; then
    DEBUG_MODE=true
    echo "=========================================="
    echo " DEBUG MODE: 跳过 strip，保留符号表"
    echo "=========================================="
fi

export NDK=/home/pisces312/android-ndk-r27d
export BASEDIR=/mnt/d/nili/3rd_party_projects/ffmpeg-kit
export AAR_PATH="$BASEDIR/android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar"

echo "=========================================="
echo " 1. Packaging AAR (Gradle)"
echo "=========================================="
rm -rf "$BASEDIR/android/ffmpeg-kit-android-lib/build"
cd "$BASEDIR/android"
cmd.exe /c "gradlew.bat ffmpeg-kit-android-lib:assembleRelease"
echo ">>> AAR packaged"

if [ "$DEBUG_MODE" == "true" ]; then
    echo "=========================================="
    echo " DEBUG MODE: 跳过 strip，符号表保留"
    echo "=========================================="
else
    echo "=========================================="
    echo " 2. Stripping debug symbols"
    echo "=========================================="
    STRIP=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip
    TMPDIR=$(mktemp -d)

    unzip -o "$AAR_PATH" -d "$TMPDIR" > /dev/null

    find "$TMPDIR" -name "*.so" | while read so; do
        echo ">>> Stripping: $(basename $so)"
        $STRIP --strip-debug "$so" 2>/dev/null || true
    done

    cd "$TMPDIR"
    zip -r "$AAR_PATH" . > /dev/null
    cd "$BASEDIR"
    rm -rf "$TMPDIR"
    echo ">>> Stripped and repackaged"
fi

echo "=========================================="
echo " AAR build complete!"
echo " AAR location:"
ls -la "$AAR_PATH"
echo "=========================================="
