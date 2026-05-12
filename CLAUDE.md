# FFmpeg Kit 8.1 - Claude Code Context

## Project Overview

Custom build of FFmpeg Kit for Android arm64-v8a based on FFmpeg 8.1, with GPL libraries (x264, x265, lame) and MediaCodec hardware encoding/decoding.

## Key Documentation

| Document | Path | Description |
|----------|------|-------------|
| Build Plan | [docs/build-plan.md](docs/build-plan.md) | FFmpeg 6.0→8.1 migration plan |
| Build Log | [docs/build-log.md](docs/build-log.md) | Build environment, scripts, and results |
| FFmpeg Modifications | [docs/ffmpeg-modifications.md](docs/ffmpeg-modifications.md) | All changes to FFmpeg source in this fork |

## Project Structure

```
ffmpeg-kit/
├── src/                          # Source code (untouched)
│   ├── ffmpeg/                   # FFmpeg 8.1
│   ├── x264/, x265/, lame/      # External libraries
│   └── cpu-features/
├── android/
│   ├── jni/Android.mk           # JNI build config
│   ├── ffmpeg-kit-android-lib/
│   │   ├── src/main/cpp/        # Modified fftools + JNI bridge
│   │   └── src/main/java/       # Java API (FFprobeKit, etc.)
│   └── libs/arm64-v8a/          # FFmpeg .so files (copied by build_aar.sh)
├── prebuilt/android-arm64/ffmpeg/  # Built FFmpeg libraries
├── docs/                        # Project documentation
├── build_ffmpeg_full.sh         # Build FFmpeg + deps (WSL)
└── build_aar.sh                 # Package AAR (WSL → Windows Gradle)
```

## Build Commands

```bash
# Build FFmpeg + dependencies (WSL)
./build_ffmpeg_full.sh

# Rebuild only FFmpeg (skip deps)
FORCE_FFMPEG=1 ./build_ffmpeg_full.sh

# Package AAR (WSL, calls Windows Gradle)
./build_aar.sh
```

## FFmpeg Modifications

All modifications to FFmpeg source are documented in [docs/ffmpeg-modifications.md](docs/ffmpeg-modifications.md). Changes are made ONLY to the `fftools_*.c` copies in `android/ffmpeg-kit-android-lib/src/main/cpp/`, never to `src/ffmpeg/`.

## Current Known Modifications

1. **ffprobe stdout → av_log redirect** (`fftools_tw_stdout.c`): Redirects ffprobe JSON output from printf/stdout to av_log
2. **Remove log_callback_help override** (`fftools_ffprobe.c`, `fftools_opt_common.c`): Removed `av_log_set_callback(log_callback_help)` so JNI callback is never bypassed
3. **Help display → stderr** (`fftools_cmdutils.c`): `log_callback_help`, `show_help_options`, `show_help_children` write to stderr instead of stdout
4. **SDP output → av_log** (`fftools_ffmpeg_mux.c`): SDP description goes through av_log
5. **All printf → av_log** (`fftools_opt_common.c`): 103 printf calls converted to av_log (codec/format/protocol listing, license, help)
