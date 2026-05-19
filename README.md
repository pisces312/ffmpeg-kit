# FFmpegKit - FFmpeg 8.1 Full-GPL for Android

Custom build of FFmpegKit based on FFmpeg 8.1 with full GPL libraries and MediaCodec hardware encoding/decoding.

## Features

- FFmpeg 8.1 (full-gpl)
- External libraries: x264, x265, lame (mp3lame)
- Android MediaCodec hardware encoding/decoding: h264, hevc
- **Critical stability fix: resolved native SIGSEGV crash in JNI layer** — fixed global state pollution causing segment fault on repeated `ffmpeg_execute()` calls
- Target: Android arm64-v8a, API 24+
- Output: AAR package with JNI bridge

> **Stability Note:** This fork fixes a critical segment fault (SIGSEGV) in the native JNI/C layer that occurred when calling `ffmpeg_execute()` multiple times. The root cause was FFmpeg's original design as a single-run command-line tool — it relies heavily on global variables and static state. When wrapped as a library via JNI, these global states (e.g., array counters like `nb_input_files`) were not properly reset between executions, leading to crashes, memory leaks, and state pollution. The fix involved properly resetting global array counters in `ffmpeg_cleanup()` (see `fftools_ffmpeg.c`). This was a particularly nasty bug to track down due to its location at the Java/Native boundary, and its resolution significantly improves runtime reliability for production use.

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

## Documentation

| Document | Description |
|----------|-------------|
| [docs/build-plan.md](docs/build-plan.md) | FFmpeg 6.0→8.1 migration plan |
| [docs/build-log.md](docs/build-log.md) | Build environment, scripts, and results |
| [docs/ffmpeg-modifications.md](docs/ffmpeg-modifications.md) | All changes to FFmpeg source in this fork |

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
  docs/                   # Project documentation
```
