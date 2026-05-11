#!/bin/bash
set -e

# ============================================================
# FFmpeg 8.1 Full-GPL Build Script for Android arm64-v8a
# Builds x264, x265, lame, then FFmpeg with all linked
# Set FORCE_FFMPEG=1 to rebuild only FFmpeg
# ============================================================

export NDK=/home/pisces312/android-ndk-r25b
export TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64
export TARGET=aarch64-linux-android24
export CC=$TOOLCHAIN/bin/${TARGET}-clang
export CXX=$TOOLCHAIN/bin/${TARGET}-clang++
export AR=$TOOLCHAIN/bin/llvm-ar
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip

export BASEDIR=/mnt/d/nili/3rd_party_projects/ffmpeg-kit
export PREFIX=$BASEDIR/prebuilt/android-arm64/ffmpeg
export FFMPEG_SRC=/home/pisces312/ffmpeg-8.1

# Ensure pkg-config is in PATH
export PATH="/usr/local/bin:/usr/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

# Install pkg-config wrapper if real pkg-config not available
if ! command -v pkg-config &>/dev/null; then
    echo ">>> pkg-config not found, creating wrapper..."
    cat > /usr/local/bin/pkg-config << 'PKEOF'
#!/bin/bash
PC_PATH="${PKG_CONFIG_PATH:-.}"
ACTION="" PKGS="" STATIC=""
for arg in "$@"; do
    case "$arg" in
        --modversion) ACTION="modversion" ;;
        --libs) ACTION="libs" ;;
        --cflags) ACTION="cflags" ;;
        --static) STATIC=1 ;;
        --exists|--atleast-version=*|--max-version=*|--exact-version=*) ACTION="exists" ;;
        --print-errors) ;;
        --silence-errors) ;;
        --validate) ;;
        --*) ;;
        *>=*|*<=*|*=*) ;;
        *) PKGS="$PKGS $arg" ;;
    esac
done
for pkg in $PKGS; do
    pc="$PC_PATH/${pkg}.pc"
    if [ ! -f "$pc" ]; then
        echo "Package $pkg was not found in the pkg-config search path." >&2
        echo "Perhaps you should add the directory containing '${pkg}.pc'" >&2
        echo "to the PKG_CONFIG_PATH environment variable." >&2
        exit 1
    fi
    prefix=$(grep "^prefix=" "$pc" | cut -d= -f2)
    exec_prefix="$prefix"
    libdir="${exec_prefix}/lib"
    includedir="${prefix}/include"
    case "$ACTION" in
        modversion) grep "^Version:" "$pc" | cut -d' ' -f2 ;;
        libs)
            libs=$(grep "^Libs:" "$pc" | sed 's/^Libs: *//')
            [ "$STATIC" = 1 ] && libs="$libs $(grep "^Libs.private:" "$pc" | sed 's/^Libs.private: *//')"
            echo "$libs" | sed "s|\${libdir}|$libdir|g; s|\${prefix}|$prefix|g; s|\${exec_prefix}|$exec_prefix|g"
            ;;
        cflags)
            grep "^Cflags:" "$pc" | sed 's/^Cflags: *//' | sed "s|\${includedir}|$includedir|g; s|\${prefix}|$prefix|g"
            ;;
        exists) exit 0 ;;
    esac
done
PKEOF
    chmod +x /usr/local/bin/pkg-config
fi

mkdir -p $PREFIX/lib $PREFIX/include

echo "=========================================="
echo " PREFIX: $PREFIX"
echo " NDK:    $NDK"
echo "=========================================="

# ------ x264 (skip if already built) ------
if [ ! -f "$PREFIX/lib/libx264.a" ] || [ ! -f "$PREFIX/lib/pkgconfig/x264.pc" ]; then
    echo -e "\n>>> Building x264..."
    cd $BASEDIR/src/x264
    make distclean 2>/dev/null || true
    ./configure \
        --prefix=$PREFIX \
        --enable-pic \
        --enable-static \
        --disable-cli \
        --host=aarch64-linux-android \
        --cross-prefix=$TOOLCHAIN/bin/llvm-
    make -j$(nproc)
    make install
    echo ">>> x264 done"
else
    echo -e "\n>>> x264 already built, skipping"
fi

# ------ x265 (skip if already built) ------
if [ ! -f "$PREFIX/lib/libx265.a" ] || [ ! -f "$PREFIX/lib/pkgconfig/x265.pc" ]; then
    echo -e "\n>>> Building x265..."
    cd $BASEDIR/src/x265/source
    rm -rf CMakeCache.txt CMakeFiles
    cmake \
        -DCMAKE_INSTALL_PREFIX=$PREFIX \
        -DCMAKE_C_COMPILER=$CC \
        -DCMAKE_CXX_COMPILER=$CXX \
        -DCMAKE_SYSTEM_NAME=Generic \
        -DENABLE_SHARED=0 \
        -DENABLE_CLI=0 \
        -DHIGH_BIT_DEPTH=1 \
        -DENABLE_ASSEMBLY=0 \
        -DSTATIC_LINK_CRT=1 \
        -DENABLE_PIC=1 .
    make -j$(nproc)
    make install
    echo ">>> x265 done"
else
    echo -e "\n>>> x265 already built, skipping"
fi

# ------ lame (skip if already built) ------
if [ ! -f "$PREFIX/lib/libmp3lame.a" ] || [ ! -f "$PREFIX/lib/pkgconfig/mp3lame.pc" ]; then
    echo -e "\n>>> Building lame..."
    cd $BASEDIR/src/lame
    make distclean 2>/dev/null || true
    if [ ! -f "./configure" ]; then
        echo ">>> Extracting lame-3.100.tar.gz..."
        cd $BASEDIR/src
        rm -rf lame
        tar xzf /home/pisces312/lame-3.100.tar.gz
        mv lame-3.100 lame
        cd lame
    fi
    ./configure \
        --prefix=$PREFIX \
        --host=aarch64-linux-android \
        --disable-shared \
        --enable-static \
        --disable-frontend \
        CC="$CC" \
        CXX="$CXX" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        STRIP="$STRIP"
    make -j$(nproc)
    make install
    echo ">>> lame done"
else
    echo -e "\n>>> lame already built, skipping"
fi

# ------ FFmpeg 8.1 (use FORCE_FFMPEG=1 to rebuild) ------
if [ "$FORCE_FFMPEG" = "1" ] || [ ! -f "$PREFIX/lib/libavcodec.so" ]; then
    echo -e "\n>>> Building FFmpeg 8.1..."
    cd $FFMPEG_SRC
    make distclean 2>/dev/null || true
    ./configure \
        --prefix=$PREFIX \
        --target-os=android \
        --arch=aarch64 \
        --cpu=armv8-a \
        --cc=$CC \
        --cxx=$CXX \
        --ar=$AR \
        --ranlib=$RANLIB \
        --strip=$STRIP \
        --enable-cross-compile \
        --enable-gpl \
        --enable-nonfree \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libmp3lame \
        --enable-mediacodec \
        --enable-jni \
        --enable-encoder=h264_mediacodec \
        --enable-encoder=hevc_mediacodec \
        --enable-decoder=h264_mediacodec \
        --enable-decoder=hevc_mediacodec \
        --enable-shared \
        --disable-static \
        --disable-doc \
        --disable-programs \
        --extra-cflags="-I$PREFIX/include" \
        --extra-ldflags="-L$PREFIX/lib"
    make -j$(nproc)
    make install
    echo ">>> FFmpeg done"
else
    echo -e "\n>>> FFmpeg already built, skipping"
fi

echo -e "\n=========================================="
echo " Build complete!"
echo " .so files:"
ls -la $PREFIX/lib/*.so
echo "=========================================="
