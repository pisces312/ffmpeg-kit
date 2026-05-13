# FFmpeg-kit 重新构建计划（修复 swresample crash）

## 背景

StreamClip 在 H265 硬编码 + AAC 音频编码时闪退，根因定位到 `libswresample.so` 的 NEON 优化路径。上次构建（约 2026-05-10）缺少关键 Android arm64 编译参数，可能导致 NEON 汇编代码生成不正确。

## 修改内容

### 脚本修改
文件：`build_ffmpeg_full.sh`

**补充的编译参数：**
- `--sysroot=$TOOLCHAIN/sysroot`
- `CFLAGS`: `-march=armv8-a -std=c99 -Wno-unused-function -fstrict-aliasing -DANDROID_NDK -fPIC -DANDROID -D__ANDROID__ -D__ANDROID_MIN_SDK_VERSION__=24 -Os -ffunction-sections -fdata-sections`
- `LDFLAGS`: `-Wl,--gc-sections -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -Wl,--hash-style=both`

### 编码器列表（与上次构建一致）

| 类型 | 编码器 |
|------|--------|
| 外部库 | libx264, libx264rgb, libx265, libmp3lame |
| 硬件 MediaCodec | h264_mediacodec, hevc_mediacodec, av1_mediacodec, mpeg4_mediacodec, vp8_mediacodec, vp9_mediacodec |
| 关键内置音频 | aac, ac3, eac3, flac, opus, vorbis, mp2 |
| 关键内置视频 | mpeg1/2/4, h261/263, vp8/9, mjpeg |

## 构建步骤

### 步骤 1：构建 FFmpeg 8.1 + 外部库（.so）
```bash
cd /mnt/d/nili/3rd_party_projects/ffmpeg-kit
bash build_ffmpeg_full.sh
```

**输出位置：**
- `prebuilt/android-arm64/ffmpeg/lib/*.so`
- 关键文件：`libavcodec.so`, `libswresample.so`, `libavutil.so`, `libavformat.so`, `libavfilter.so`, `libswscale.so`

**验证方法：**
1. 检查 .so 文件是否生成
2. 对比文件大小（应与上次接近，libswresample.so 约 88KB）
3. 检查 ELF 头：`readelf -h libswresample.so | grep Flags`
4. 检查 NEON 符号：`readelf -s libswresample.so | grep neon`

### 步骤 2：构建 JNI + 打包 AAR
```bash
cd /mnt/d/nili/3rd_party_projects/ffmpeg-kit
bash build_aar.sh
```

**输出位置：**
- `android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar`

**验证方法：**
1. AAR 文件大小（上次约 12-15MB strip 后）
2. 解压检查 jni/arm64-v8a/ 下所有 .so 存在
3. 安装到 StreamClip 测试采样率转换功能

## 环境要求

- WSL Ubuntu
- NDK: `/home/pisces312/android-ndk-r25b`
- FFmpeg 源码: `/home/pisces312/ffmpeg-8.1`
- 外部库源码: `src/x264`, `src/x265`, `src/lame`
- Windows Gradle: 用于步骤 2 的 AAR 打包

## 回滚方案

如需回滚到上次构建的 .so：
```bash
# 从 git 恢复（如果 prebuilt 在 git 中）
# 或从备份复制
cp prebuilt/android-arm64/ffmpeg/lib/*.so.bak prebuilt/android-arm64/ffmpeg/lib/
```

## 状态跟踪

- [x] 步骤 1 完成（2026-05-13 13:00）
- [x] 步骤 1 验证通过
- [ ] 步骤 2 完成
- [ ] 步骤 2 验证通过
- [ ] StreamClip 测试通过（采样率转换不复现 crash）

## 构建日志

### 第一次 FFmpeg-only 构建
**时间：** 2026-05-13 13:00（约 6 分钟）
**结果：** FFmpeg 单独重新构建，外部库跳过

### 第二次完整构建（x264/x265/lame + FFmpeg）
**时间：** 2026-05-13 13:09 - 13:21
**过程：**
1. x264 重新构建（含 `-march=armv8-a -fstrict-aliasing -Os`）
2. x265 重新构建（含 CMAKE_C/CXX_FLAGS 优化参数）
3. lame 重新构建（含 CFLAGS 优化参数）
4. FFmpeg 重新链接（修复 x265.pc，添加 `--extra-libs="-lm -lc++"`）

**验证结果：**
- 所有 .so 文件时间戳已更新（May 13 13:21）
- libavcodec.so: 16,320,576 → 15,922,072 字节（-398KB，优化效果）
- libswresample.so: 88,760 → 89,496 字节
- ELF 头正确：ELF64, AArch64
- NEON 汇编文件已编译：`resample.o`, `audio_convert_neon.o`
- NEON 指令确认存在于 .so 中：`fmla`, `addv`, `dup` 等
- configure 参数确认包含：`-march=armv8-a`, `-fstrict-aliasing`, `-Os`

**脚本修改记录：**
- `build_ffmpeg_full.sh`：补充 x264/x265/lame/FFmpeg 的编译参数
- `x265.pc`：修复 Libs.private（`-lm -lc++`）
- FFmpeg configure：添加 `--extra-libs="-lm -lc++"`

**下一步：** 步骤 2（构建 JNI + 打包 AAR）
