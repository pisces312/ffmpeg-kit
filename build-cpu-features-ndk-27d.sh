#!/bin/bash
set -e

# ============================================================
# Build cpu-features NDK compat library for Android arm64-v8a
# ============================================================

export NDK=/home/pisces312/android-ndk-r27d
export TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64
export TARGET=aarch64-linux-android24
export CC=$TOOLCHAIN/bin/${TARGET}-clang
export AR=$TOOLCHAIN/bin/llvm-ar

export BASEDIR=/mnt/d/nili/3rd_party_projects/ffmpeg-kit
export SRC=$BASEDIR/src/cpu-features
export OUT=$BASEDIR/prebuilt/android-arm64/cpu-features

echo "=========================================="
echo " Building cpu-features NDK compat"
echo " NDK:    $NDK"
echo "=========================================="

# Clean old build
rm -rf $SRC/build-android
mkdir -p $SRC/build-android
mkdir -p $OUT/lib
mkdir -p $OUT/include/ndk_compat

cd $SRC/build-android

cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-24 \
    -DCMAKE_C_COMPILER=$CC \
    -DCMAKE_AR=$AR \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$OUT

make -j$(nproc)
make install

# The CMake install puts libndk_compat.a under lib/ and headers under include/ndk_compat/
# Verify the output
echo ""
echo "Build complete!"
echo "  Library: $OUT/lib/libndk_compat.a"
echo "  Header:  $OUT/include/ndk_compat/cpu-features.h"
ls -la $OUT/lib/libndk_compat.a
