#!/bin/bash
# Simple pkg-config wrapper for FFmpeg build
PKG_CONFIG_PATH="/mnt/d/nili/3rd_party_projects/ffmpeg-kit/prebuilt/android-arm64/ffmpeg/lib/pkgconfig"

# Find the real pkg-config or use a simple implementation
if command -v pkg-config &>/dev/null; then
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH" exec pkg-config "$@"
fi

# Simple implementation
for arg in "$@"; do
    case "$arg" in
        --modversion)
            pkg="$2"
            pc="$PKG_CONFIG_PATH/${pkg}.pc"
            if [ -f "$pc" ]; then
                grep "^Version:" "$pc" | cut -d' ' -f2
                exit 0
            fi
            exit 1
            ;;
        --libs)
            pkg="$2"
            pc="$PKG_CONFIG_PATH/${pkg}.pc"
            if [ -f "$pc" ]; then
                grep "^Libs:" "$pc" | sed 's/^Libs: *//'
                exit 0
            fi
            exit 1
            ;;
        --cflags)
            pkg="$2"
            pc="$PKG_CONFIG_PATH/${pkg}.pc"
            if [ -f "$pc" ]; then
                grep "^Cflags:" "$pc" | sed 's/^Cflags: *//'
                exit 0
            fi
            exit 1
            ;;
    esac
done
