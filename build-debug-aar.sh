#!/bin/bash
set -e

# ============================================================
# ffmpeg-kit Debug AAR 构建脚本
# ============================================================
# 与 build_aar.sh 的区别：
# 1. 保留 .so 的符号表（不执行 strip）
# 2. 不修改 FFmpeg 编译参数，仅跳过 strip 步骤
# 3. 输出文件带 -debug 后缀，避免与 release 混淆
#
# 用途：用于 native crash 调试，tombstone 可输出函数名和行号
# ============================================================

export NDK=/home/pisces312/android-ndk-r27d
export BASEDIR=/mnt/d/nili/3rd_party_projects/ffmpeg-kit
export ANDROID_HOME=/mnt/d/nili/dev/android_sdk
export AAR_SRC="$BASEDIR/android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar"
export AAR_DST="$BASEDIR/ffmpeg-kit-debug.aar"

echo "=========================================="
echo " Building ffmpeg-kit DEBUG AAR"
echo "  - Symbol table: KEPT"
echo "  - Strip step: SKIPPED"
echo "=========================================="

echo ""
echo "[1/3] Building JNI library (ndk-build)..."
cd "$BASEDIR/android"
rm -rf obj/local
$NDK/ndk-build \
    NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=jni/Android.mk \
    NDK_APPLICATION_MK=jni/Application.mk \
    APP_ALLOW_MISSING_DEPS=true

echo ""
echo "[2/3] Copying FFmpeg .so files..."
FFMPEG_LIBS=$BASEDIR/prebuilt/android-arm64/ffmpeg/lib
JNI_LIBS=$BASEDIR/android/libs/arm64-v8a
mkdir -p "$JNI_LIBS"
for so in libavcodec.so libavdevice.so libavfilter.so libavformat.so libavutil.so libswresample.so libswscale.so; do
    if [ -f "$FFMPEG_LIBS/$so" ]; then
        cp -vf "$FFMPEG_LIBS/$so" "$JNI_LIBS/$so"
    fi
done
echo ">>> libavcodec.so size: $(stat -c%s $JNI_LIBS/libavcodec.so)"

echo ""
echo "[3/3] Packaging AAR (Gradle assembleRelease)..."
rm -rf "$BASEDIR/android/ffmpeg-kit-android-lib/build"
cd "$BASEDIR/android"
cmd.exe /c "gradlew.bat ffmpeg-kit-android-lib:assembleRelease"

echo ""
echo "=========================================="
echo " Debug AAR build complete!"
echo "=========================================="
echo ""

# 复制到带 -debug 后缀的文件
cp "$AAR_SRC" "$AAR_DST"

# 验证符号表是否保留
echo ">>> Verifying symbol table..."
TMPDIR=$(mktemp -d)
unzip -o "$AAR_DST" -d "$TMPDIR" >/dev/null

for so in "$TMPDIR"/jni/arm64-v8a/*.so; do
    name=$(basename "$so")
    if command -v aarch64-linux-android-readelf >/dev/null 2>&1; then
        symtab=$(aarch64-linux-android-readelf -S "$so" 2>/dev/null | grep -c '.symtab' || echo 0)
        if [ "$symtab" -gt 0 ]; then
            echo "    [OK] $name - symbol table PRESENT"
        else
            echo "    [WARN] $name - symbol table MISSING"
        fi
    else
        size=$(stat -c%s "$so")
        echo "    $name - size: ${size} bytes (check manually with readelf -S)"
    fi
done

rm -rf "$TMPDIR"

echo ""
echo ">>> Output: $AAR_DST"
ls -la "$AAR_DST"
echo ""
echo "Usage in StreamClip:"
echo "  implementation(files(\"libs/ffmpeg-kit-debug.aar\"))"
echo ""
