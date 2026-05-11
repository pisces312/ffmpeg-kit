# FFmpegKit 8.1 Android AAR 构建记录

## 构建环境

### 工具链路径
| 工具 | 路径 | 版本 |
|------|------|------|
| NDK | /home/pisces312/android-ndk-r25b | r25b |
| FFmpeg源码 | /home/pisces312/ffmpeg-8.1 | 8.1 |
| ffmpeg-kit项目 | /home/pisces312/ffmpeg-kit-8.1 | 8.1 |
| 预编译外部库 | /home/pisces312/android_build/arm64-v8a-minimal/ | - |
| Android SDK (Windows) | D:\nili\dev\android_sdk | API 33 |
| JDK (WSL) | /usr/bin/javac | OpenJDK 21 |

### WSL环境
- OS: Windows 11 + WSL Ubuntu
- 目标架构: arm64-v8a

---

## FFmpeg编译参数

### 完整configure命令
```bash
./configure \
    --prefix=/home/pisces312/android_build/arm64-v8a \
    --target-os=android \
    --arch=aarch64 \
    --cpu=armv8-a \
    --cc=/home/pisces312/android-ndk-r25b/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang \
    --cxx=/home/pisces312/android-ndk-r25b/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang++ \
    --strip=/home/pisces312/android-ndk-r25b/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip \
    --enable-cross-compile \
    --disable-debug \
    --enable-static \
    --enable-shared \
    --enable-small \
    --enable-gpl \
    --enable-nonfree \
    --enable-neon \
    --disable-doc \
    --disable-ffplay \
    --disable-everything \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libmp3lame \
    --enable-encoder='libx264,libx265,aac,libmp3lame,flac,h264_v4l2m2m' \
    --enable-decoder='h264,hevc,h264_v4l2m2m,hevc_v4l2m2m,aac,aac_latm,mp3,mp3float,flac' \
    --enable-muxer='mp4,mov,matroska,avi,flv,flac' \
    --enable-demuxer='mp4,mov,matroska,avi,flv,flac,aac,mp3' \
    --enable-filter='scale,crop,trim,concat,volume,fade,rotate,transpose,overlay,format,fps,afade,acrossfade,aformat,atrim,volumedetect,cropdetect' \
    --enable-protocol=file \
    --enable-bsf='h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc' \
    --enable-parser='h264,hevc,aac,mpegaudio,flac' \
    --enable-swscale \
    --enable-swresample \
    --enable-avfilter \
    --enable-avformat \
    --enable-avcodec \
    --enable-avutil \
    --extra-cflags='-O3 -Wall -fPIE -fPIC -I/home/pisces312/android_build/arm64-v8a-minimal/include' \
    --extra-ldflags='-pie -L/home/pisces312/android_build/arm64-v8a-minimal/lib' \
    --pkg-config-flags=--static
```

### 编译和安装
```bash
cd /home/pisces312/ffmpeg-8.1
make clean
make -j$(nproc)
make install
```

---

## 启用的编解码器完整列表

### 视频编码器 (Encoders)
| 编码器 | 类型 | 说明 |
|--------|------|------|
| libx264 | 软件 | H.264/AVC编码 |
| libx265 | 软件 | H.265/HEVC编码 |
| h264_v4l2m2m | 硬件 | H.264 V4L2 M2M硬件编码 |

### 音频编码器 (Encoders)
| 编码器 | 类型 | 说明 |
|--------|------|------|
| aac | 软件 | AAC音频编码(FFmpeg内置) |
| libmp3lame | 软件 | MP3音频编码 |
| flac | 软件 | FLAC无损音频编码 |

### 视频解码器 (Decoders)
| 解码器 | 类型 | 说明 |
|--------|------|------|
| h264 | 软件 | H.264/AVC解码 |
| hevc | 软件 | H.265/HEVC解码 |
| h264_v4l2m2m | 硬件 | H.264 V4L2 M2M硬件解码 |
| hevc_v4l2m2m | 硬件 | H.265/HEVC V4L2 M2M硬件解码 |

### 音频解码器 (Decoders)
| 解码器 | 说明 |
|--------|------|
| aac | AAC解码 |
| aac_latm | AAC LATM解码 |
| mp3 | MP3解码 |
| mp3float | MP3浮点解码 |
| flac | FLAC解码 |

### 复用器 (Muxers) - 输出容器格式
| 格式 | 说明 |
|------|------|
| mp4 | MP4容器 |
| mov | QuickTime容器 |
| matroska | MKV容器 |
| avi | AVI容器 |
| flv | FLV容器 |
| flac | FLAC音频文件 |

### 解复用器 (Demuxers) - 输入容器格式
| 格式 | 说明 |
|------|------|
| mp4 | MP4容器 |
| mov | QuickTime容器 |
| matroska | MKV容器 |
| avi | AVI容器 |
| flv | FLV容器 |
| flac | FLAC音频文件 |
| aac | AAC音频流 |
| mp3 | MP3音频流 |

### 滤镜 (Filters)
scale, crop, trim, concat, volume, fade, rotate, transpose, overlay, format, fps, afade, acrossfade, aformat, atrim, volumedetect, cropdetect

### BSF (Bitstream Filters)
| BSF | 说明 |
|-----|------|
| h264_mp4toannexb | H.264 MP4转Annex B |
| hevc_mp4toannexb | HEVC MP4转Annex B |
| aac_adtstoasc | AAC ADTS转ASC |

### Parsers
h264, hevc, aac, mpegaudio, flac

### 协议
- file (本地文件)

---

## 硬件编解码说明

| 编解码器 | 对应标准 | API | Android兼容性 |
|----------|----------|-----|---------------|
| h264_v4l2m2m | H.264/AVC | V4L2 M2M | 部分设备 |
| hevc_v4l2m2m | H.265/HEVC | V4L2 M2M | 部分设备 |
| h264_mediacodec | H.264/AVC | MediaCodec | 未启用 |
| hevc_mediacodec | H.265/HEVC | MediaCodec | 未启用 |

**说明:**
- **hevc_mediacodec** = H.265/HEVC的Android MediaCodec硬件编解码器
- **h264_mediacodec** = H.264/AVC的Android MediaCodec硬件编解码器
- **V4L2 M2M** = Video4Linux2 Memory-to-Memory接口，在部分Android设备上可用
- **MediaCodec** = Android标准硬件编解码API，兼容性更好，当前未启用

如需启用MediaCodec，需在FFmpeg configure时添加:
```bash
--enable-mediacodec
--enable-decoder='h264_mediacodec,hevc_mediacodec'
```

---

## /home/pisces312/ffmpeg-kit-8.1/src 可删除的源码

当前构建只使用了x264、x265、lame，以下源码目录可以删除:

### 已使用 (保留)
| 目录 | 用途 |
|------|------|
| ffmpeg | FFmpeg核心源码 |
| lame | MP3编码器 |
| x264 | H.264编码器 |
| x265 | H.265编码器 |
| cpu-features | CPU特性检测 |

### 未使用 (可删除)
| 目录 | 用途 |
|------|------|
| chromaprint | 音频指纹 |
| dav1d | AV1解码器 |
| expat | XML解析 |
| fontconfig | 字体配置 |
| freetype | 字体渲染 |
| fribidi | 阿拉伯语/希伯来语 |
| giflib | GIF支持 |
| gmp | 大数运算 |
| gnutls | TLS/SSL |
| harfbuzz | 文本整形 |
| jpeg | JPEG支持 |
| kvazaar | HEVC编码器 |
| libaom | AV1编解码器 |
| libass | 字幕渲染 |
| libiconv | 字符编码转换 |
| libilbc | iLBC音频编解码 |
| libogg | OGG容器 |
| libpng | PNG支持 |
| libsamplerate | 采样率转换 |
| libsndfile | 音频文件IO |
| libtheora | Theora视频编码 |
| libuuid | UUID生成 |
| libvidstab | 视频稳定 |
| libvorbis | Vorbis音频编码 |
| libvpx | VP8/VP9编解码 |
| libwebp | WebP支持 |
| libxml2 | XML解析 |
| nettle | 加密库 |
| opencore-amr | AMR编解码 |
| openh264 | H.264编码器 |
| openssl | SSL/TLS |
| opus | Opus音频编解码 |
| rubberband | 音频变速 |
| sdl | SDL库 |
| shine | MP3编码器 |
| snappy | 压缩库 |
| soxr | 采样率转换 |
| speex | Speex音频编解码 |
| srt | SRT协议 |
| tesseract | OCR文字识别 |
| tiff | TIFF支持 |
| twolame | MP2编码器 |
| vo-amrwbenc | AMR-WB编码 |
| xvidcore | MPEG-4编码 |
| zimg | 图像处理 |

### 删除命令
```bash
cd /home/pisces312/ffmpeg-kit-8.1/src
mkdir -p ../src_backup
mv chromaprint dav1d expat fontconfig freetype fribidi giflib gmp gnutls harfbuzz jpeg kvazaar libaom libass libiconv libilbc libogg libpng libsamplerate libsndfile libtheora libuuid libvidstab libvorbis libvpx libwebp libxml2 nettle opencore-amr openh264 openssl opus rubberband sdl shine snappy soxr speex srt tesseract tiff twolame vo-amrwbenc xvidcore zimg ../src_backup/
```

---

## 构建步骤总结

### 1. 编译外部库 (x264, x265, lame)
```bash
# 预编译库已存在于:
/home/pisces312/android_build/arm64-v8a-minimal/lib/
```

### 2. 编译FFmpeg
```bash
cd /home/pisces312/ffmpeg-8.1
# 使用上面的configure命令
make -j$(nproc)
make install
```

### 3. 准备ffmpeg-kit源码
```bash
# 复制fftools文件并重命名
python3 /home/pisces312/ffmpeg-kit-8.1/build_scripts/copy_textformat.py

# 修复include路径
python3 /home/pisces312/ffmpeg-kit-8.1/build_scripts/fix_includes.py
```

### 4. 修改源码
- fftools_ffmpeg.c: program_name改为非const
- fftools_ffprobe.c: main()改名为ffprobe_execute()
- fftools_cmdutils.h: 修改extern声明
- ffmpegkit.c: 添加SAF桩函数

### 5. 编译JNI库
```bash
cd /home/pisces312/ffmpeg-kit-8.1/android
/home/pisces312/android-ndk-r25b/ndk-build \
    NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=jni/Android.mk \
    NDK_APPLICATION_MK=jni/Application.mk
```

### 6. 编译Java并打包AAR
```bash
# 编译Java
javac -source 11 -target 11 -cp android.jar -d build/classes \
    src/main/java/com/arthenica/ffmpegkit/*.java

# 创建classes.jar
jar cf build/classes.jar -C build/classes .

# 打包AAR (ZIP格式)
# 包含: AndroidManifest.xml, classes.jar, jni/arm64-v8a/*.so
```

---

## 最终产物
- **文件:** ffmpeg-kit-8.1.aar
- **大小:** ~4.2MB
- **架构:** arm64-v8a
- **FFmpeg版本:** 8.1
- **外部库:** x264, x265, lame
- **包含:** 10个.so文件, 32个Java类
