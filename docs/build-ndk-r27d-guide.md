# ffmpeg-kit NDK r27d 构建指南

> 构建目标：Android arm64-v8a，包含 x264、x265 4.2、lame、MediaCodec
> 构建环境：WSL Ubuntu + Windows Gradle
> 构建日期：2026-05-13

---

## 前置条件

1. **NDK r27d** 已下载并解压到 `/home/pisces312/android-ndk-r27d`
2. **FFmpeg 8.1 源码** 在 `/home/pisces312/ffmpeg-8.1`
3. **x264、x265、lame 源码** 在 `src/` 目录下
4. **完整 ffmpeg include 目录** 已就位（见下方"内部头文件"章节）
5. **cpu-features 目录** 已就位（见下方"cpu-features"章节）

---

## 构建脚本

### 1. `build-ffmpeg-ndk-27d.sh` — 编译 FFmpeg 及依赖库

从 `build_ffmpeg_full.sh` 复制，NDK 路径改为 r27d：

```bash
export NDK=/home/pisces312/android-ndk-r27d
export TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64
export TARGET=aarch64-linux-android24
```

**编译顺序**：x264 -> x265 -> lame -> FFmpeg 8.1

### 2. `build-aar-ndk-r27d.sh` — 编译 JNI + 打包 AAR

从 `build_aar.sh` 复制，关键修改：

```bash
export NDK=/home/pisces312/android-ndk-r27d

# ndk-build 增加 APP_ALLOW_MISSING_DEPS=true
$NDK/ndk-build \
    NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=jni/Android.mk \
    NDK_APPLICATION_MK=jni/Application.mk \
    APP_ALLOW_MISSING_DEPS=true
```

---

## 构建过程与问题修复

### 问题 1：x265 `pkg-config` 找不到

**现象**：
```
ERROR: x265 not found using pkg-config
```

**根因**：x265 4.2 的 `make install` **不生成 `x265.pc`** 文件。

**修复**：在 `build-ffmpeg-ndk-27d.sh` 的 x265 构建段，手动创建 `x265.pc`：

```bash
if [ ! -f "$PREFIX/lib/pkgconfig/x265.pc" ]; then
    cat > "$PREFIX/lib/pkgconfig/x265.pc" << "EOF"
prefix=/mnt/d/nili/3rd_party_projects/ffmpeg-kit/prebuilt/android-arm64/ffmpeg
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: x265
Description: H.265/HEVC video encoder
Version: 4.2
Libs: -L${libdir} -lx265
Libs.private: -lm -lc++
Cflags: -I${includedir}
EOF
fi
```

**此修复已写入 `build-ffmpeg-ndk-27d.sh`**，重新构建时会自动处理。

---

### 问题 2：`cpu-features` 目录缺失导致 ndk-build 失败

**现象**：
```
Android NDK: LOCAL_SRC_FILES points to a missing file
prebuilt/android-arm64/cpu-features/lib/libndk_compat.a
```

**根因**：用户清理遗留目录时误删了 `prebuilt/android-arm64/cpu-features/`。

**修复**：从备份 `ffmpeg-kit-prebuilt-backup-20260513-2134` 恢复 `cpu-features/` 目录。

**来源说明**：`cpu-features` 来自 Google 的 `cpu_features` 库（ffmpeg-kit fork 版本 `arthenica/cpu_features` v0.8.0），通过 CMake + NDK 构建生成。产物为：
- `lib/libndk_compat.a` — 静态库
- `include/ndk_compat/cpu-features.h` — 头文件

**用途**：`ffmpegkit_abidetect.c` 编译时依赖 `cpu-features` 静态库来检测 ABI/NEON 支持。原始构建系统中 `libvpx` 和 `openh264` 也依赖它。**不可删除**。

---

### 问题 3：NDK r27d `c++_shared` 依赖检查失败

**现象**：
```
Module ffmpegkit depends on undefined modules: c++_shared
```

**根因**：NDK r27d（相比 r25b）的 `ndk-build` 对共享库依赖检查更严格。`Application.mk` 中 `APP_STL := c++_shared` 不会自动让模块依赖 `c++_shared`，需要显式声明。

**修复**：在 `ndk-build` 命令中增加 `APP_ALLOW_MISSING_DEPS=true`：

```bash
$NDK/ndk-build \
    NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=jni/Android.mk \
    NDK_APPLICATION_MK=jni/Application.mk \
    APP_ALLOW_MISSING_DEPS=true
```

---

### 问题 4：`config.h` 和内部头文件缺失

**现象**：
```
'config.h' file not found
'libavutil/thread.h' file not found
'libavformat/network.h' file not found
```

**根因**：FFmpeg 的 `make install` **只安装公开 API 头文件**（如 `libavcodec/avcodec.h`），**不安装内部头文件**。但 ffmpeg-kit 的 JNI 层（`ffmpegkit.c`、`fftools_*.c` 等）编译时依赖大量 FFmpeg 内部头文件。

**这些头文件包括**：
- `config.h` — 编译配置宏（定义了启用了哪些编解码器/特性）
- `libavutil/thread.h` — 线程抽象层
- `libavutil/internal.h` — 内部工具函数
- `libavutil/timer.h` — 性能计时
- `libavformat/network.h` — 网络相关定义
- `libavformat/os_support.h` — 平台兼容性
- `libavformat/url.h` — URL 协议内部结构
- `libavcodec/mathops.h` — 数学运算宏
- `compat/` 目录 — 编译器/平台兼容性头文件

**原始 ffmpeg-kit 是如何处理的？**

官方构建脚本 `scripts/android/ffmpeg.sh` 第 511-536 行，在 `make install` 后有一大段 **"MANUALLY ADD REQUIRED HEADERS"**，手动从 FFmpeg 源码目录把这些头文件复制到安装目录：

```bash
# 官方脚本片段
overwrite_file "${BASEDIR}"/src/ffmpeg/config.h "${FFMPEG_LIBRARY_PATH}"/include/config.h
overwrite_file "${BASEDIR}"/src/ffmpeg/libavutil/thread.h "${FFMPEG_LIBRARY_PATH}"/include/libavutil/thread.h
# ... 还有 20+ 个文件
```

**修复**：从备份 `ffmpeg-kit-prebuilt-backup-20260513-2134` 恢复完整 `prebuilt/android-arm64/ffmpeg/include/` 目录（从 150 个文件恢复到 1044 个文件）。

**这些头文件从哪里来？**

它们来自 **FFmpeg 源码目录**（`/home/pisces312/ffmpeg-8.1`），不是 `make install` 生成的。原始构建系统会在 `make install` 后手动从源码复制。

> ⚠️ **重要**：当前 `build-ffmpeg-ndk-27d.sh` 缺少 `make install` 后复制内部头文件的步骤。如果从头重新运行脚本，会再次丢失这些头文件。建议在脚本中加入这一步（参考官方脚本），或每次构建后从源码手动复制。

---

## 完整构建流程

### 步骤 1：编译依赖库和 FFmpeg

```bash
cd /mnt/d/nili/3rd_party_projects/ffmpeg-kit
./build-ffmpeg-ndk-27d.sh
```

此脚本会依次编译 x264、x265、lame、FFmpeg 8.1，产物在 `prebuilt/android-arm64/ffmpeg/lib/` 下。

### 步骤 2：编译 JNI + 打包 AAR

```bash
./build-aar-ndk-r27d.sh
```

此脚本执行：
1. `ndk-build` 编译 JNI 层（`libffmpegkit.so`、`libffmpegkit_abidetect.so`）
2. 复制 FFmpeg `.so` 到 `libs/arm64-v8a/`
3. Windows Gradle 打包 AAR
4. `llvm-strip` 去除调试符号

### 最终产物

```
android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar
```

包含：
- FFmpeg 7 个库：`libavcodec.so`、`libavdevice.so`、`libavfilter.so`、`libavformat.so`、`libavutil.so`、`libswresample.so`、`libswscale.so`
- JNI 层：`libffmpegkit.so`、`libffmpegkit_abidetect.so`
- C++ 运行时：`libc++_shared.so`

---

## NDK r25b vs r27d 差异总结

| 方面 | NDK r25b (LLVM 14) | NDK r27d (LLVM 18) |
|------|-------------------|-------------------|
| `ndk-build` 依赖检查 | 较宽松 | 更严格，需要 `APP_ALLOW_MISSING_DEPS=true` |
| 编译器优化 | LLVM 14 | LLVM 18，可能生成不同 NEON 代码 |
| `c++_shared` 处理 | 自动处理 | 需要显式声明或允许缺失 |
| cpu-features | 正常工作 | 正常工作 |

---

## 文件索引

| 文件 | 说明 |
|------|------|
| `build-ffmpeg-ndk-27d.sh` | FFmpeg 及依赖库编译脚本 |
| `build-aar-ndk-r27d.sh` | JNI 编译 + AAR 打包脚本 |
| `prebuilt/android-arm64/ffmpeg/` | FFmpeg 编译产物（.so + .a + include） |
| `prebuilt/android-arm64/cpu-features/` | cpu-features 静态库和头文件 |
| `android/jni/Android.mk` | ndk-build 主 Makefile |
| `android/jni/Application.mk` | ndk-build 应用配置 |
| `android/jni/cpu-features/Android.mk` | cpu-features 预构建库引用 |
| `scripts/android/ffmpeg.sh` | 官方 FFmpeg 构建脚本（含头文件复制逻辑） |
