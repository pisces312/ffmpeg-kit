# FFmpeg 8.1 Android arm64-v8a 构建文档

## 1. 构建概览

| 项目 | 值 |
|------|------|
| FFmpeg 版本 | 8.1 |
| 目标平台 | Android |
| 目标架构 | arm64-v8a (API 24) |
| NDK 版本 | r25b |
| 许可证 | GPL (启用 libx264/x265) |
| 编译模式 | 非 LTS |
| 产物类型 | 共享库 (.so) |

---

## 2. 构建环境

### 2.1 WSL 环境 (Linux 编译)

| 工具 | 路径 | 版本/说明 |
|------|------|-----------|
| OS | WSL Ubuntu | Windows 11 + WSL |
| NDK | `/home/pisces312/android-ndk-r25b` | r25b |
| 编译器 | `aarch64-linux-android24-clang` | Clang 14.0.6 |
| FFmpeg 源码 | `/home/pisces312/ffmpeg-8.1` | 8.1 |
| 项目目录 | `/mnt/d/nili/3rd_party_projects/ffmpeg-kit` | |

### 2.2 Windows 环境 (AAR 打包)

| 工具 | 路径 | 版本 |
|------|------|------|
| Android SDK | `D:\nili\dev\android_sdk` | API 36.1.0 |
| JDK | `D:\nili\dev\AndroidStudio\jbr` | 21.0.10 |
| Android Studio | `D:\nili\dev\AndroidStudio` | 2025.3.3 |

### 2.3 工具链变量

```bash
export NDK=/home/pisces312/android-ndk-r25b
export TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64
export TARGET=aarch64-linux-android24
export CC=$TOOLCHAIN/bin/${TARGET}-clang
export CXX=$TOOLCHAIN/bin/${TARGET}-clang++
export AR=$TOOLCHAIN/bin/llvm-ar
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip
```

---

## 3. 外部库编译

### 3.1 x264 (H.264 软件编码)

| 项目 | 值 |
|------|------|
| 静态库 | `libx264.a` (2.2 MB) |
| 输出位置 | `prebuilt/android-arm64/ffmpeg/lib/` |

```bash
cd src/x264
./configure \
    --prefix=$PREFIX \
    --enable-pic \
    --enable-static \
    --disable-cli \
    --host=aarch64-linux-android \
    --cross-prefix=$TOOLCHAIN/bin/llvm-
make -j$(nproc)
make install
```

**关键参数说明：**
- `--enable-pic` — 位置无关代码，必须（最终要链接进 .so）
- `--enable-static` — 生成静态库，由 FFmpeg 链接
- `--disable-cli` — 不编译命令行工具

### 3.2 x265 (H.265 软件编码)

| 项目 | 值 |
|------|------|
| 静态库 | `libx265.a` (2.3 MB) |
| 输出位置 | `prebuilt/android-arm64/ffmpeg/lib/` |

```bash
cd src/x265/source
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
```

**关键参数说明：**
- `HIGH_BIT_DEPTH=1` — 启用 10-bit 编码
- `ENABLE_ASSEMBLY=0` — 禁用汇编（Android NDK 交叉编译兼容性）
- `ENABLE_SHARED=0` — 只生成静态库
- `STATIC_LINK_CRT=1` — 静态链接 C 运行时

**注意：** x265 是 C++ 库，链接时需要 `-lc++ -lm -ldl`。已修改 `x265.pc` 将依赖放到 `Libs` 行。

### 3.3 LAME (MP3 编码)

| 项目 | 值 |
|------|------|
| 静态库 | `libmp3lame.a` (497 KB) |
| 输出位置 | `prebuilt/android-arm64/ffmpeg/lib/` |

```bash
cd src/lame
./configure \
    --prefix=$PREFIX \
    --host=aarch64-linux-android \
    --disable-shared \
    --enable-static \
    --disable-frontend \
    CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP"
make -j$(nproc)
make install
```

**关键参数说明：**
- `--disable-frontend` — 不编译 lame 命令行工具
- `--enable-static` — 生成静态库

---

## 4. FFmpeg 编译

### 4.1 Configure 参数

```bash
cd /home/pisces312/ffmpeg-8.1
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
```

### 4.2 参数详解

| 参数 | 作用 |
|------|------|
| `--target-os=android` | 目标操作系统 |
| `--arch=aarch64` | ARM 64-bit 架构 |
| `--cpu=armv8-a` | CPU 微架构 (ARMv8-A) |
| `--enable-cross-compile` | 启用交叉编译 |
| `--enable-gpl` | GPL 许可 (x264/x265 必需) |
| `--enable-nonfree` | 非自由软件许可 |
| `--enable-libx264` | 链接 x264 库 |
| `--enable-libx265` | 链接 x265 库 |
| `--enable-libmp3lame` | 链接 LAME 库 |
| `--enable-mediacodec` | Android MediaCodec 硬件编解码 |
| `--enable-jni` | JNI 支持 (MediaCodec 依赖) |
| `--enable-encoder=h264_mediacodec` | H.264 硬件编码器 |
| `--enable-encoder=hevc_mediacodec` | H.265 硬件编码器 |
| `--enable-decoder=h264_mediacodec` | H.264 硬件解码器 |
| `--enable-decoder=hevc_mediacodec` | H.265 硬件解码器 |
| `--enable-shared` | 生成共享库 (.so) |
| `--disable-static` | 不生成静态库 |
| `--disable-doc` | 不编译文档 |
| `--disable-programs` | 不编译 ffmpeg/ffprobe 命令行工具 |

### 4.3 编译与安装

```bash
make -j$(nproc)
make install
```

---

## 5. 编解码器清单

### 5.1 视频编码器

| 编码器 | 类型 | 说明 |
|--------|------|------|
| `libx264` | 软件 | H.264/AVC 编码 (GPL) |
| `libx264rgb` | 软件 | H.264 RGB 编码 (GPL) |
| `libx265` | 软件 | H.265/HEVC 编码 (GPL) |
| `h264_mediacodec` | 硬件 | H.264 MediaCodec 编码 |
| `hevc_mediacodec` | 硬件 | H.265 MediaCodec 编码 |
| `av1_mediacodec` | 硬件 | AV1 MediaCodec 编码 |
| `mpeg4_mediacodec` | 硬件 | MPEG-4 MediaCodec 编码 |
| `vp8_mediacodec` | 硬件 | VP8 MediaCodec 编码 |
| `vp9_mediacodec` | 硬件 | VP9 MediaCodec 编码 |
| `aac` | 软件 | AAC 音频编码 (内置) |
| `flac` | 软件 | FLAC 音频编码 (内置) |
| `libmp3lame` | 软件 | MP3 音频编码 (GPL) |

### 5.2 视频解码器

| 解码器 | 类型 | 说明 |
|--------|------|------|
| `h264` | 软件 | H.264/AVC 解码 |
| `hevc` | 软件 | H.265/HEVC 解码 |
| `h264_mediacodec` | 硬件 | H.264 MediaCodec 解码 |
| `hevc_mediacodec` | 硬件 | H.265 MediaCodec 解码 |
| `mpeg2_mediacodec` | 硬件 | MPEG-2 MediaCodec 解码 |
| `mpeg4_mediacodec` | 硬件 | MPEG-4 MediaCodec 解码 |
| `vp8_mediacodec` | 硬件 | VP8 MediaCodec 解码 |
| `vp9_mediacodec` | 硬件 | VP9 MediaCodec 解码 |
| `av1_mediacodec` | 硬件 | AV1 MediaCodec 解码 |
| `aac` | 软件 | AAC 解码 |
| `aac_fixed` | 软件 | AAC 定点解码 |
| `aac_latm` | 软件 | AAC LATM 解码 |
| `flac` | 软件 | FLAC 解码 |

### 5.3 音频编码器

| 编码器 | 类型 | 说明 |
|--------|------|------|
| `aac` | 软件 | AAC 音频编码 (内置) |
| `libmp3lame` | 软件 | MP3 音频编码 (GPL) |
| `flac` | 软件 | FLAC 音频编码 (内置) |

### 5.4 音频解码器

| 解码器 | 类型 | 说明 |
|--------|------|------|
| `aac` | 软件 | AAC 解码 |
| `mp3` | 软件 | MP3 解码 |
| `flac` | 软件 | FLAC 解码 |

---

## 6. 容器格式

### 6.1 Muxer (封装)

`mp4`, `mov`, `matroska`, `avi`, `flv`, `flac`, `aac`, `mp3`, `ogg`, `opus`, `wav`, `webm`, `mpegts`, `hls`, `dash`, `3gp`, `m4a`, `m4v`, `ipod`, `psp`, `avif`, `webm_chunk`, `null`, `segment`, `tee`

### 6.2 Demuxer (解封装)

支持 500+ 种格式，常用：

`mp4`, `mov`, `matroska`, `avi`, `flv`, `flac`, `aac`, `mp3`, `ogg`, `opus`, `wav`, `webm`, `mpegts`, `hls`, `dash`, `3gp`, `m4a`, `rm`, `asf`, `swf`, `gif`, `apng`, `image2`, `concat`, `sdp`, `rtp`

### 6.3 协议

`file`, `pipe`, `tcp`, `udp`, `http`, `https`, `rtmp`, `rtsp`, `hls`, `concat`, `cache`, `crypto`, `data`, `fd`, `ftp`, `async`, `unix`

---

## 7. 滤镜

### 7.1 视频滤镜 (部分)

`scale`, `crop`, `trim`, `concat`, `fade`, `rotate`, `transpose`, `overlay`, `format`, `fps`, `drawbox`, `edgedetect`, `hue`, `lut`, `noise`, `pad`, `transpose`, `vflip`, `hflip`, `thumbnail`, `zoompan`, `xfade`, `colorkey`, `chromakey`, `gblur`, `boxblur`, `unsharp`, `eq`, `curves`, `colorbalance`, `normalize`, `histogram`, `vectorscope`, `waveform`

### 7.2 音频滤镜 (部分)

`volume`, `afade`, `acrossfade`, `aformat`, `atrim`, `volumedetect`, `aresample`, `aecho`, `aecho`, `chorus`, `compand`, `equalizer`, `highpass`, `lowpass`, `pan`, `loudnorm`, `dynaudnorm`, `stereotools`, `stereowiden`

### 7.3 音视频混合滤镜

`concat`, `showwaves`, `showfreqs`, `showspectrum`, `avectorscope`, `ahistogram`, `aphasemeter`

---

## 8. Bitstream Filter

`h264_mp4toannexb`, `hevc_mp4toannexb`, `aac_adtstoasc`, `h264_metadata`, `hevc_metadata`, `h264_redundant_pps`, `extract_extradata`, `remove_extradata`, `null`, `dump_extradata`, `chomp`, `noise`, `vp9_metadata`, `av1_metadata`

---

## 9. 预编译产物

### 9.1 FFmpeg 共享库

| 库文件 | 大小 | 说明 |
|--------|------|------|
| `libavcodec.so` | 16 MB | 音视频编解码 (含 x264/x265/lame 静态链接) |
| `libavformat.so` | 2.5 MB | 容器格式读写 |
| `libavfilter.so` | 3.9 MB | 滤镜框架 |
| `libavutil.so` | 698 KB | 通用工具库 |
| `libswresample.so` | 87 KB | 音频重采样 |
| `libswscale.so` | 947 KB | 图像缩放/像素格式转换 |
| `libavdevice.so` | 63 KB | 设备输入输出 |

### 9.2 外部库静态库

| 库文件 | 大小 | 说明 |
|--------|------|------|
| `libx264.a` | 2.2 MB | H.264 编码 (已静态链接到 libavcodec.so) |
| `libx265.a` | 2.3 MB | H.265 编码 (已静态链接到 libavcodec.so) |
| `libmp3lame.a` | 497 KB | MP3 编码 (已静态链接到 libavcodec.so) |

### 9.3 输出路径

```
prebuilt/android-arm64/ffmpeg/
├── lib/
│   ├── libavcodec.so
│   ├── libavformat.so
│   ├── libavfilter.so
│   ├── libavutil.so
│   ├── libswresample.so
│   ├── libswscale.so
│   ├── libavdevice.so
│   ├── pkgconfig/
│   │   ├── libavcodec.pc
│   │   ├── libavformat.pc
│   │   └── ...
│   └── *.a (外部库静态库，保留在这里供 FFmpeg 链接)
└── include/
    ├── libavcodec/
    ├── libavformat/
    ├── libavfilter/
    ├── libavutil/
    ├── libswresample/
    ├── libswscale/
    └── libavdevice/
```

---

## 10. 构建脚本

### 10.1 `build_ffmpeg_full.sh` — 编译外部库 + FFmpeg

```bash
# 完整构建 (x264 + x265 + lame + FFmpeg)
./build_ffmpeg_full.sh

# 仅重新构建 FFmpeg (跳过外部库)
FORCE_FFMPEG=1 ./build_ffmpeg_full.sh
```

**构建流程：**
1. 检查 x264 静态库是否存在 → 不存在则编译
2. 检查 x265 静态库是否存在 → 不存在则编译
3. 检查 lame 静态库是否存在 → 不存在则编译
4. 检查 FFmpeg 共享库是否存在 → 不存在或 `FORCE_FFMPEG=1` 则编译

**pkg-config 处理：** 脚本自动创建 pkg-config wrapper 到 `/usr/local/bin/pkg-config`

### 10.2 `build_aar.sh` — JNI 编译 + AAR 打包

```bash
./build_aar.sh
```

**构建流程：**
1. **ndk-build** — 编译 JNI 桥接层 (`libffmpegkit.so`)
2. **复制 .so** — 将 FFmpeg 共享库复制到 `android/libs/arm64-v8a/`
3. **Gradle 打包** — 通过 `cmd.exe` 调用 Windows Gradle 生成 AAR
4. **strip 调试符号** — 解压 AAR → strip .so → 重新打包

**最终产物：** `android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar` (~12 MB)

---

## 11. JNI 构建配置

### 11.1 `android/jni/Android.mk`

- 模块名：`libffmpegkit.so`
- 链接 FFmpeg 共享库：`libavcodec.so`, `libavformat.so`, `libavfilter.so`, `libavutil.so`, `libswresample.so`, `libswscale.so`, `libavdevice.so`
- 依赖：`cpu-features` (静态库)
- 编译标志：`-Wall -Werror -Wno-unused-parameter -Wno-switch -Wno-sign-compare`

### 11.2 源文件列表

```
ffmpegkit.c, ffprobekit.c, ffmpegkit_exception.c,
fftools_cmdutils.c, fftools_ffmpeg.c, fftools_ffprobe.c,
fftools_ffmpeg_mux.c, fftools_ffmpeg_mux_init.c, fftools_ffmpeg_demux.c,
fftools_ffmpeg_opt.c, fftools_opt_common.c, fftools_ffmpeg_hw.c,
fftools_ffmpeg_filter.c, fftools_ffmpeg_dec.c, fftools_ffmpeg_enc.c,
fftools_ffmpeg_sched.c, fftools_sync_queue.c, fftools_thread_queue.c,
fftools_textformat.c, fftools_tf_compact.c, fftools_tf_default.c,
fftools_tf_flat.c, fftools_tf_ini.c, fftools_tf_json.c,
fftools_tf_mermaid.c, fftools_tf_xml.c, fftools_tw_avio.c,
fftools_tw_buffer.c, fftools_tw_stdout.c, fftools_graphprint.c,
fftools_resman.c, fftools_graph_css.c, fftools_graph_html.c
```

---

## 12. 源码修改

所有修改都在 JNI 层的 `fftools_*.c` 副本中，**不修改原始 FFmpeg 源码** (`src/ffmpeg/`)。

详细修改记录见 [ffmpeg-modifications.md](../docs/ffmpeg-modifications.md)

### 修改摘要

| # | 文件 | 修改内容 |
|---|------|----------|
| 1 | `fftools_tw_stdout.c` | stdout → av_log 重定向 (ffprobe JSON 输出) |
| 2 | `fftools_ffprobe.c` | 移除 `av_log_set_callback(log_callback_help)` |
| 3 | `fftools_opt_common.c` | 移除 log_callback_help，103 个 printf → av_log |
| 4 | `fftools_cmdutils.c` | log_callback_help + help 函数 → stderr |
| 5 | `fftools_ffmpeg_mux.c` | SDP 输出 → av_log |

---

## 13. 已知问题与注意事项

### 13.1 pkg-config

WSL 下默认可能没有 pkg-config，脚本会自动创建 wrapper 脚本到 `/usr/local/bin/pkg-config`。

### 13.2 x265 链接依赖

x265 是 C++ 库，需要 `-lc++ -lm -ldl`。已修改 `x265.pc` 将这些依赖放到 `Libs` 行而非 `Libs.private`，否则 FFmpeg configure 的链接测试会失败。

### 13.3 LTS 模式已移除

原 ffmpeg-kit 使用 `android/build/.lts` 标记文件切换 LTS/非LTS 预编译库路径。本项目只用非LTS模式（`APP_PLATFORM := android-21`），已从 `Android.mk` 中移除所有 LTS 条件分支。

### 13.4 静态库保留

`build_ffmpeg_full.sh` 不会删除 x264/x265/lame 的静态库 (.a)，因为 FFmpeg 需要链接它们。

### 13.5 WSL → Windows Gradle

WSL 下无法直接运行 Gradle（Android SDK build tools 是 Windows 二进制），`build_aar.sh` 通过 `cmd.exe` 调用 Windows Gradle。

---

## 14. 重新构建步骤

```bash
# 1. 完整构建 FFmpeg + 外部库 (WSL)
cd /mnt/d/nili/3rd_party_projects/ffmpeg-kit
./build_ffmpeg_full.sh

# 2. 仅重新构建 FFmpeg (跳过外部库)
FORCE_FFMPEG=1 ./build_ffmpeg_full.sh

# 3. 编译 JNI + 打包 AAR (WSL)
./build_aar.sh
```

---

## 15. 产物验证

构建完成后验证：

```bash
# 检查 .so 文件
ls -lh prebuilt/android-arm64/ffmpeg/lib/*.so

# 检查 AAR
ls -lh android/ffmpeg-kit-android-lib/build/outputs/aar/

# 验证 FFmpeg 配置 (WSL)
cat /home/pisces312/ffmpeg-8.1/ffbuild/config.mak | head -5
```
