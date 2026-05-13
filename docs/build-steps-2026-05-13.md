# 2026-05-13 ffmpeg-kit 重新构建记录

## 背景

StreamClip 在 H265 硬编码 + AAC 音频编码时闪退，根因定位到 `libswresample.so` 的 NEON 优化路径。上次构建缺少关键 Android arm64 编译参数，可能导致 NEON 汇编代码生成不正确。

## 修改的脚本

**直接修改的文件：** `build_ffmpeg_full.sh`（位于 `D:\nili\3rd_party_projects\ffmpeg-kit\build_ffmpeg_full.sh`）

修改内容：
1. x264 configure 添加 `--extra-cflags="-march=armv8-a -fstrict-aliasing -fPIC -DANDROID -Os"`
2. x265 cmake 添加 `-DCMAKE_C_FLAGS="..." -DCMAKE_CXX_FLAGS="..."`
3. lame configure 添加 `CFLAGS="..." LDFLAGS="-Wl,--gc-sections"`
4. FFmpeg configure 添加完整参数 + `--extra-libs="-lm -lc++"`

## 实际执行的命令步骤（WSL）

### 1. 强制重新构建 x264/x265/lame

```bash
cd /mnt/d/nili/3rd_party_projects/ffmpeg-kit

# 删除旧产物（强制触发重新构建）
rm -f prebuilt/android-arm64/ffmpeg/lib/libx264.a
rm -f prebuilt/android-arm64/ffmpeg/lib/pkgconfig/x264.pc
rm -f prebuilt/android-arm64/ffmpeg/lib/libx265.a
rm -f prebuilt/android-arm64/ffmpeg/lib/libmp3lame.a
rm -f prebuilt/android-arm64/ffmpeg/lib/pkgconfig/mp3lame.pc
```

### 2. 构建外部库（x264 + x265 + lame）

```bash
bash build_ffmpeg_full.sh
# 结果：x264/x265/lame 成功构建
```

### 3. 修复 x265.pc（CMake 生成的 pkg-config 有 bug）

```bash
# 发现 x265.pc 中 Libs.private 有错误格式
# 原内容：Libs.private: -lc++ -lm -l-l:libunwind.a -ldl -l-l:libunwind.a -ldl
cat > prebuilt/android-arm64/ffmpeg/lib/pkgconfig/x265.pc << 'EOF'
prefix=/mnt/d/nili/3rd_party_projects/ffmpeg-kit/prebuilt/android-arm64/ffmpeg
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: x265
Description: H.265/HEVC video encoder
Version: 3.4
Libs: -L${libdir} -lx265
Libs.private: -lm -lc++
Cflags: -I${includedir}
EOF
```

### 4. 删除旧 FFmpeg .so 文件并重新链接

```bash
rm -f prebuilt/android-arm64/ffmpeg/lib/libavcodec.so
rm -f prebuilt/android-arm64/ffmpeg/lib/libavdevice.so
rm -f prebuilt/android-arm64/ffmpeg/lib/libavfilter.so
rm -f prebuilt/android-arm64/ffmpeg/lib/libavformat.so
rm -f prebuilt/android-arm64/ffmpeg/lib/libavutil.so
rm -f prebuilt/android-arm64/ffmpeg/lib/libswresample.so
rm -f prebuilt/android-arm64/ffmpeg/lib/libswscale.so

# 强制重新构建 FFmpeg
FORCE_FFMPEG=1 bash build_ffmpeg_full.sh
```

### 5. 验证构建结果

```bash
# 检查文件大小和时间戳
ls -la /mnt/d/nili/3rd_party_projects/ffmpeg-kit/prebuilt/android-arm64/ffmpeg/lib/*.so

# 检查 ELF 头
readelf -h /mnt/d/nili/3rd_party_projects/ffmpeg-kit/prebuilt/android-arm64/ffmpeg/lib/libswresample.so

# 检查 NEON 指令
/home/pisces312/android-ndk-r25b/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump \
    -d /mnt/d/nili/3rd_party_projects/ffmpeg-kit/prebuilt/android-arm64/ffmpeg/lib/libswresample.so | grep fmla

# 检查编译参数
strings /mnt/d/nili/3rd_party_projects/ffmpeg-kit/prebuilt/android-arm64/ffmpeg/lib/libswresample.so | grep march
```

## 遇到的问题和解决

| 问题 | 原因 | 解决 |
|------|------|------|
| x265 not found using pkg-config | CMake 生成的 x265.pc Libs.private 格式错误（`-l-l:libunwind.a`） | 手动重写 x265.pc |
| undefined symbol: log, exp, __cxa_guard_acquire | FFmpeg configure 测试 x265 时需要链接 `-lm -lc++` | FFmpeg configure 添加 `--extra-libs="-lm -lc++"` |
| 脚本换行符问题 | Windows 编辑导致 CRLF | `sed -i 's/\r$//' build_ffmpeg_full.sh` |

## 构建参数总结

### x264
```
--extra-cflags="-march=armv8-a -fstrict-aliasing -fPIC -DANDROID -Os"
```

### x265 (CMake)
```
-DCMAKE_C_FLAGS="-march=armv8-a -fstrict-aliasing -fPIC -DANDROID -Os"
-DCMAKE_CXX_FLAGS="-march=armv8-a -fstrict-aliasing -fPIC -DANDROID -Os"
```

### lame
```
CFLAGS="-march=armv8-a -fstrict-aliasing -fPIC -DANDROID -Os"
LDFLAGS="-Wl,--gc-sections"
```

### FFmpeg
```
--extra-cflags="-march=armv8-a -std=c99 -Wno-unused-function -fstrict-aliasing
                -DANDROID_NDK -fPIC -DANDROID -D__ANDROID__
                -D__ANDROID_MIN_SDK_VERSION__=24 -Os -ffunction-sections -fdata-sections
                -I$PREFIX/include"
--extra-ldflags="-L$PREFIX/lib -Wl,--gc-sections -Wl,-z,noexecstack
                 -Wl,-z,relro -Wl,-z,now -Wl,--hash-style=both"
--extra-libs="-lm -lc++"
```

## 6. AAR 打包（WSL + Windows 混合）

### 6.1 构建脚本 `build_aar.sh`

更新后的脚本支持 WSL/Windows 混合执行：
- 步骤 1（ndk-build）、步骤 2（复制 .so）、步骤 4（strip）：WSL 执行
- 步骤 3（Gradle 打包）：Windows `cmd.exe /c gradlew.bat`

关键路径配置：
```bash
export NDK=/home/pisces312/android-ndk-r25b
export BASEDIR=/mnt/d/nili/3rd_party_projects/ffmpeg-kit
export ANDROID_HOME=/mnt/d/nili/dev/android_sdk
```

### 6.2 执行命令

```bash
cd /mnt/d/nili/3rd_party_projects/ffmpeg-kit
bash build_aar.sh
```

脚本执行流程：
1. `ndk-build` 编译 JNI 层（`libffmpegkit.so` + `libffmpegkit_abidetect.so`）
2. 复制 FFmpeg `.so` 到 `android/libs/arm64-v8a/`
3. `gradlew.bat assembleRelease` 打包 AAR
4. `llvm-strip --strip-debug` 去除调试符号并重新 zip

### 6.3 替换到 StreamClip

```bash
cp /mnt/d/nili/3rd_party_projects/ffmpeg-kit/android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar \
   /mnt/d/nili/my-git-projects/StreamClip/app/libs/ffmpeg-kit-8.1.aar
```

保持原文件名 `ffmpeg-kit-8.1.aar`，无需修改 `build.gradle` 即可直接构建 APK。

## 输出文件

| 文件 | 大小 | 时间戳 |
|------|------|--------|
| libx264.a | 1,843,946 | 2026-05-13 13:09 |
| libx265.a | 2,356,072 | 2026-05-13 13:09 |
| libmp3lame.a | 426,090 | 2026-05-13 13:17 |
| libavcodec.so | 15,922,072 | 2026-05-13 13:21 |
| libswresample.so | 89,496 | 2026-05-13 13:21 |
| ffmpeg-kit-release.aar | 12,115,419 | 2026-05-13 14:29 |
