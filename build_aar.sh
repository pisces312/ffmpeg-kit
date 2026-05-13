#!/bin/bash
set -e

export NDK=/home/pisces312/android-ndk-r25b
export BASEDIR=/mnt/d/nili/3rd_party_projects/ffmpeg-kit
export ANDROID_HOME=/mnt/d/nili/dev/android_sdk
export AAR_PATH="$BASEDIR/android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar"

echo "=========================================="
echo " 1. Building JNI library (WSL)"
echo "=========================================="
cd $BASEDIR/android
rm -rf obj/local
$NDK/ndk-build \
    NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=jni/Android.mk \
    NDK_APPLICATION_MK=jni/Application.mk
echo ">>> JNI done"

echo "=========================================="
echo " 2. Copying FFmpeg .so files (after ndk-build)"
echo "=========================================="
FFMPEG_LIBS=$BASEDIR/prebuilt/android-arm64/ffmpeg/lib
JNI_LIBS=$BASEDIR/android/libs/arm64-v8a
mkdir -p "$JNI_LIBS"
for so in libavcodec.so libavdevice.so libavfilter.so libavformat.so libavutil.so libswresample.so libswscale.so; do
    if [ -f "$FFMPEG_LIBS/$so" ]; then
        cp -vf "$FFMPEG_LIBS/$so" "$JNI_LIBS/$so"
    fi
done
echo ">>> libavcodec.so size: $(stat -c%s $JNI_LIBS/libavcodec.so)"

echo "=========================================="
echo " 3. Packaging AAR (Windows Gradle)"
echo "=========================================="
rm -rf "$BASEDIR/android/ffmpeg-kit-android-lib/build"
cd $BASEDIR/android
cmd.exe /c "gradlew.bat ffmpeg-kit-android-lib:assembleRelease"
echo ">>> AAR packaged"

echo "=========================================="
echo " 4. Stripping debug symbols (WSL)"
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

echo "=========================================="
echo " Build complete!"
echo " AAR location:"
ls -la "$AAR_PATH"
echo "=========================================="
