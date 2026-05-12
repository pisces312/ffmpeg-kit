# FFmpegKit 8.1 Android AAR 构建记录

## 构建环境

### 工具链路径
| 工具 | 路径 | 版本 |
|------|------|------|
| NDK | /home/pisces312/android-ndk-r25b | r25b |
| FFmpeg源码 | /home/pisces312/ffmpeg-8.1 | 8.1 |
| ffmpeg-kit项目 | /mnt/d/nili/3rd_party_projects/ffmpeg-kit | 8.1 |
| Android SDK (Windows) | D:\nili\dev\android_sdk | API 36.1.0 |
| JDK (WSL) | OpenJDK 21 |

### WSL环境
- OS: Windows 11 + WSL Ubuntu
- 目标架构: arm64-v8a (API 24)

---

## 构建脚本

### 自动化脚本
| 脚本 | 用途 | 运行环境 |
|------|------|----------|
| `build_ffmpeg_full.sh` | 编译x264, x265, lame, FFmpeg | WSL |
| `build_aar.sh` | 编译JNI + strip + 打包AAR | WSL (调用Windows Gradle) |
| `build_aar.bat` | Windows Gradle打包AAR | Windows CMD |

### 运行方式
```bash
# 1. 编译FFmpeg + 外部库 (WSL)
cd /mnt/d/nili/3rd_party_projects/ffmpeg-kit
./build_ffmpeg_full.sh

# 2. 仅重新编译FFmpeg (跳过已编译的外部库)
FORCE_FFMPEG=1 ./build_ffmpeg_full.sh

# 3. 编译JNI + 打包AAR (WSL)
./build_aar.sh
```

---

## FFmpeg编译参数

### 外部库编译

#### x264
```bash
./configure \
    --prefix=$PREFIX \
    --enable-pic \
    --enable-static \
    --disable-cli \
    --host=aarch64-linux-android \
    --cross-prefix=$TOOLCHAIN/bin/llvm-
```

#### x265
```bash
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
```

#### lame
```bash
./configure \
    --prefix=$PREFIX \
    --host=aarch64-linux-android \
    --disable-shared \
    --enable-static \
    --disable-frontend \
    CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP"
```

### FFmpeg configure
```bash
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
    --enable-shared \
    --disable-static \
    --disable-doc \
    --disable-programs \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib"
```

---

## 启用的编解码器

### 视频编码器
| 编码器 | 类型 | 说明 |
|--------|------|------|
| libx264 | 软件 | H.264/AVC编码 |
| libx265 | 软件 | H.265/HEVC编码 |

### 音频编码器
| 编码器 | 类型 | 说明 |
|--------|------|------|
| aac | 软件 | AAC音频编码(FFmpeg内置) |
| libmp3lame | 软件 | MP3音频编码 |

### 视频解码器
| 解码器 | 说明 |
|--------|------|
| h264 | H.264/AVC解码 |
| hevc | H.265/HEVC解码 |

### 音频解码器
| 解码器 | 说明 |
|--------|------|
| aac | AAC解码 |
| mp3 | MP3解码 |

### 容器格式
mp4, mov, matroska, avi, flv, flac, aac, mp3

### 滤镜
scale, crop, trim, concat, volume, fade, rotate, transpose, overlay, format, fps, afade, acrossfade, aformat, atrim, volumedetect, cropdetect

### BSF
h264_mp4toannexb, hevc_mp4toannexb, aac_adtstoasc

---

## 构建注意事项

### pkg-config
WSL下需要确保pkg-config可用。脚本会自动创建wrapper脚本到`/usr/local/bin/pkg-config`。

### x265链接问题
x265是C++库，需要`-lc++ -lm -ldl`。已修改`x265.pc`将这些依赖放到`Libs`行而非`Libs.private`，否则FFmpeg configure的链接测试会失败。

### 静态库保留
`build_ffmpeg_full.sh`不会删除x264/x265/lame的静态库(.a)，因为FFmpeg需要链接它们。

### LTS模式已移除

原 ffmpeg-kit 使用 `android/build/.lts` 标记文件切换 LTS/非LTS 预编译库路径。本项目只用非LTS模式（`APP_PLATFORM := android-21`），已从 `Android.mk`、`ffmpeg/Android.mk`、`ffmpeg/neon/Android.mk` 中移除所有 LTS 条件分支，简化构建。库路径硬编码为 `prebuilt/android-$(TARGET_ARCH)/`。

### AAR打包
- WSL下无法直接运行Gradle (Android SDK build tools是Windows二进制)
- `build_aar.sh`通过`cmd.exe`调用Windows Gradle
- WSL下使用NDK的`llvm-strip`去除.so的调试符号以减小体积

---

## 最终产物
- **架构:** arm64-v8a
- **FFmpeg版本:** 8.1
- **外部库:** x264, x265, lame (静态链接到libavcodec.so)
- **GPL:** 启用
- **JNI库:** libffmpegkit.so
- **AAR大小:** ~12MB
- **libavcodec.so:** ~16MB (strip后)
