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

- WSL2 Ubuntu 24.04 + Android NDK r27d at `/home/pisces312/android-ndk-r27d`
- Windows Gradle (called via `cmd.exe /c "gradlew.bat"`)
- Source code in `src/ffmpeg`, `src/x264`, `src/x265`, `src/lame`

完整环境清单见 [AGENTS.md](AGENTS.md) §3。

## Documentation

| Document | Description |
|----------|-------------|
| [AGENTS.md](AGENTS.md) | **开发环境与协作约定**：环境版本、路径映射、构建命令、硬性约束 |
| [docs/ffmpeg-build.md](docs/ffmpeg-build.md) | **构建总纲（唯一事实来源）**：环境、全部 configure 参数、外部库版本、编码器取舍、踩坑登记 |
| [docs/ffmpeg-8.1.3-rebuild-plan.md](docs/ffmpeg-8.1.3-rebuild-plan.md) | 8.1.3 重建施工方案（含外部库升级决策 D1–D5） |
| [docs/ffmpeg-modifications.md](docs/ffmpeg-modifications.md) | All changes to FFmpeg source in this fork |

## Project Structure

```
ffmpeg-kit/
  build-ffmpeg-ndk-27d.sh      # 轨道 A ①：x264/x265/lame + FFmpeg 共享库
  build-jni-ndk-r27d.sh        # 轨道 A ②：ndk-build JNI + 拷贝 .so
  build-aar-ndk-r27d.sh        # 轨道 A ③：Gradle 打包 + strip
  build-cli-binary-ndk-r27d.sh # 轨道 B：CLI 静态二进制（full / minimal）
  build-cpu-features-ndk-27d.sh# libndk_compat.a
  check-aar-ffmpeg-version.sh  # AAR 版本 / SONAME 校验
  build_scripts/               # port_fftools.py / copy_textformat.py / fix_includes.py
  android/                     # Android library project
    jni/                       # JNI build config (Android.mk / Application.mk)
    libs/arm64-v8a/            # FFmpeg .so files (copied by build-jni-*.sh)
    ffmpeg-kit-android-lib/    # Java wrapper + cpp/ 移植层
  prebuilt/android-arm64/      # Built FFmpeg libraries + pkgconfig
  out/cli/                     # 轨道 B 产出
  src/                         # Source code (ffmpeg, x264, x265, lame, cpu-features)
  docs/                        # Project documentation
```

> `build_ffmpeg_full.sh` / `build_aar.sh` 为**旧脚本，已弃用**，仅留作参考。
