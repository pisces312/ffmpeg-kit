# FFmpegKit - FFmpeg 8.1 Full-GPL for Android

Custom build of FFmpegKit based on FFmpeg 8.1 with full GPL libraries and MediaCodec hardware encoding/decoding.

## Features

- FFmpeg 8.1 (full-gpl)
- External libraries: x264, x265, lame (mp3lame)
- Android MediaCodec hardware encoding/decoding: h264, hevc
- Target: Android arm64-v8a, API 24+
- Output: AAR package with JNI bridge

## Build Scripts

### `build_ffmpeg_full.sh` (run in WSL)

Builds x264, x265, lame, and FFmpeg from source using Android NDK r25b.

```bash
bash build_ffmpeg_full.sh
```

- Set `FORCE_FFMPEG=1` to rebuild only FFmpeg (skip x264/x265/lame)
- Output: `prebuilt/android-arm64/ffmpeg/lib/*.so`

### `build_aar.sh` (run in WSL)

Builds JNI library via ndk-build, copies FFmpeg .so files, packages AAR with Gradle, and strips debug symbols.

```bash
bash build_aar.sh
```

Steps:
1. ndk-build JNI library
2. Copy FFmpeg .so files from prebuilt/ to android/libs/ (after ndk-build to avoid overwriting)
3. Gradle assembleRelease
4. Strip debug symbols from AAR

Output: `android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar`

## Prerequisites

- WSL with Android NDK r25b at `/home/pisces312/android-ndk-r25b`
- Windows Gradle (called via `cmd.exe /c "gradlew.bat"`)
- Source code in `src/ffmpeg`, `src/x264`, `src/x265`, `src/lame`

## Project Structure

```
ffmpeg-kit/
  build_ffmpeg_full.sh    # Build FFmpeg + dependencies
  build_aar.sh            # Package AAR
  android/                # Android library project
    jni/                  # JNI source (C bridge)
    libs/arm64-v8a/       # FFmpeg .so files (copied by build_aar.sh)
    ffmpeg-kit-android-lib/ # Java wrapper library
  prebuilt/               # Built FFmpeg libraries
  src/                    # Source code (ffmpeg, x264, x265, lame)
```
