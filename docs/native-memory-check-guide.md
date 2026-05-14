# ffmpeg-kit Native 层内存问题排查指南

> 用于检查 ffmpeg-kit JNI/C 代码中的内存泄漏、全局状态污染、越界访问等问题。

---

## 1. 背景

ffmpeg-kit 将 FFmpeg 命令行工具封装为 Android 可调用的库。FFmpeg 原本设计为**单次执行进程退出**的模式，大量依赖全局变量和静态状态。当通过 JNI 多次调用 `ffmpeg_execute()` 时，这些全局状态如果没有正确清理，会导致：

- 第二次执行时崩溃（SIGSEGV）
- 内存泄漏（未释放的 AVFormatContext、AVCodecContext 等）
- 状态污染（上一次执行的配置影响下一次）

---

## 2. 静态代码分析

### 2.1 Cppcheck（推荐，快速）

Cppcheck 是一款轻量级静态分析工具，无需编译即可检测 C/C++ 代码中的常见问题。

#### 安装

```bash
# Ubuntu/WSL
sudo apt update
sudo apt install cppcheck
```

#### 使用

```bash
cd /mnt/d/nili/3rd_party_projects/ffmpeg-kit

cppcheck \
    --enable=all \
    --inconclusive \
    --std=c11 \
    -I android/ffmpeg-kit-android-lib/src/main/cpp \
    android/ffmpeg-kit-android-lib/src/main/cpp/*.c \
    2>&1 | tee docs/cppcheck-report.txt
```

#### 重点关注项

| 检查项 | 说明 |
|--------|------|
| `memleak` | 内存泄漏（malloc 未 free） |
| `resourceLeak` | 资源泄漏（文件未关闭） |
| `nullPointer` | 空指针解引用 |
| `uninitvar` | 未初始化变量 |
| `deallocuse` | 释放后使用（use-after-free） |

#### 示例输出

```
[fftools_ffmpeg.c:354]: (warning) Variable 'nb_input_files' is not reset after freeing 'input_files'
```

---

### 2.2 Clang Static Analyzer

Clang 自带的静态分析器，深度路径分析，能发现更复杂的逻辑问题。

#### 使用

```bash
# 需要安装 clang-tools
sudo apt install clang-tools

# 分析单个文件
scan-build clang -c \
    -I android/ffmpeg-kit-android-lib/src/main/cpp \
    android/ffmpeg-kit-android-lib/src/main/cpp/fftools_ffmpeg.c
```

---

## 3. 动态运行时检测

### 3.1 AddressSanitizer (ASan)

ASan 是 Google 开发的内存错误检测工具，能检测：
- 堆/栈/全局内存越界
- Use-after-free
- Use-after-return
- Double-free

#### 配置 Application.mk

```makefile
# android/jni/Application.mk

# 添加 ASan 编译选项
APP_CFLAGS += -fsanitize=address -fno-omit-frame-pointer
APP_LDFLAGS += -fsanitize=address

# 注意：ASan 会显著增加 so 体积和运行开销，仅用于 debug 版本
```

#### 重新编译

```bash
./build-debug-aar.sh
```

#### 运行时输出

ASan 会在检测到内存错误时自动输出详细报告到 logcat：

```
==12345==ERROR: AddressSanitizer: heap-use-after-free on address 0x0007b86f17600
READ of size 8 in thread T123
    #0 0x7b055a634c in of_open fftools_ffmpeg_mux_init.c:3403
    #1 0x7b055a62f0 in create_streams fftools_ffmpeg_mux_init.c:2035
```

---

### 3.2 LeakSanitizer (LSan)

LSan 通常与 ASan 一起使用，检测内存泄漏。

#### 启用

```makefile
# Application.mk 中同时添加
APP_CFLAGS += -fsanitize=address,leak
APP_LDFLAGS += -fsanitize=address,leak
```

#### 运行时检查

在 App 退出时，LSan 会输出泄漏报告：

```
==12345==ERROR: LeakSanitizer: detected memory leaks
Direct leak of 1024 byte(s) in 1 object(s) allocated from:
    #0 0x7b055a1234 in av_malloc
    #1 0x7b055b5678 in ffmpeg_parse_options fftools_ffmpeg_opt.c:1450
```

---

### 3.3 Android Studio Profiler

虽然 Profiler 主要监控 Java 堆，但可以通过以下方式辅助：

1. **Native Memory Profiler**（Android Studio 4.1+）
   - 需使用 Android 11+ 设备
   - 可查看 native 堆分配和释放

2. **Memory Heap Dump**
   - 对比多次压缩前后的 Java 堆，间接发现 JNI 层泄漏

---

## 4. 手动代码审查要点

### 4.1 全局变量重置检查清单

基于 `fftools_ffmpeg.c` 中 `ffmpeg_cleanup()` 的经验，检查以下全局变量：

```c
// 数组 + 计数器对
InputFile   **input_files   = NULL;    int nb_input_files   = 0;
OutputFile  **output_files  = NULL;    int nb_output_files  = 0;
FilterGraph **filtergraphs  = NULL;    int nb_filtergraphs  = 0;
Decoder     **decoders      = NULL;    int nb_decoders      = 0;

// static 变量（文件作用域）
static atomic_int transcode_init_done = 0;
static volatile int ffmpeg_exited = 0;
static volatile int received_sigterm = 0;
static volatile int received_nb_signals = 0;
```

**检查规则**：
- [ ] `av_freep(&array)` 后是否重置了 `nb_array = 0`
- [ ] `static` 变量是否在每次执行前重置
- [ ] 信号处理函数是否重复注册

### 4.2 搜索所有 static 变量

```bash
cd /mnt/d/nili/3rd_party_projects/ffmpeg-kit/android/ffmpeg-kit-android-lib/src/main/cpp

grep -rn "static " *.c | grep -v "static int\|static void\|static const" | sort
```

重点关注：
- `static` 指针变量（可能悬空）
- `static` 结构体/对象（状态残留）
- `static` 计数器/标志位（未重置）

### 4.3 FFmpeg 对象生命周期检查

| 对象类型 | 分配函数 | 释放函数 | 检查点 |
|----------|----------|----------|--------|
| AVFormatContext | `avformat_alloc_context()` | `avformat_free_context()` | 输入/输出文件关闭 |
| AVCodecContext | `avcodec_alloc_context3()` | `avcodec_free_context()` | 编码器/解码器释放 |
| AVFrame | `av_frame_alloc()` | `av_frame_free()` | 滤镜/编解码缓冲 |
| AVPacket | `av_packet_alloc()` | `av_packet_free()` | 数据包处理 |
| AVDictionary | `av_dict_set()` | `av_dict_free()` | 选项字典 |

---

## 5. 实战流程

### 场景：修复连续执行崩溃

```bash
# Step 1: 静态扫描
cppcheck --enable=all -I android/ffmpeg-kit-android-lib/src/main/cpp \
    android/ffmpeg-kit-android-lib/src/main/cpp/*.c 2>&1 | tee cppcheck-report.txt

# Step 2: 检查全局变量重置
grep -n "av_freep\|nb_" android/ffmpeg-kit-android-lib/src/main/cpp/fftools_ffmpeg.c

# Step 3: 检查 static 变量
grep -rn "static " android/ffmpeg-kit-android-lib/src/main/cpp/*.c | grep -v "const"

# Step 4: 构建 ASan 版本
# 修改 Application.mk 添加 -fsanitize=address
./build-debug-aar.sh

# Step 5: 运行测试并抓取 logcat
adb logcat -c
adb logcat -v threadtime *:V | tee asan-log.txt
# 在 App 中连续执行两次压缩

# Step 6: 分析日志
grep -E "ERROR:|AddressSanitizer|LeakSanitizer" asan-log.txt
```

---

## 6. 已知问题记录

### 已修复

| 问题 | 文件 | 修复 | 时间 |
|------|------|------|------|
| 全局数组计数器未重置 | `fftools_ffmpeg.c` | `ffmpeg_cleanup()` 中加 `nb_* = 0` | 2026-05-14 |

### 待检查

- [ ] `static` 变量 `transcode_init_done`、`ffmpeg_exited` 是否需要重置
- [ ] `sch`（scheduler）对象是否正确释放
- [ ] 信号处理函数 `sigterm_handler` 是否重复注册
- [ ] `avformat_network_init()` / `avformat_network_deinit()` 调用次数平衡

---

## 7. 参考文档

- [StreamClip Native Crash 抓取指南](../../StreamClip/docs/capture-native-crash-log.md)
- [ffmpeg-kit 8.1 双次执行崩溃分析](../../StreamClip/docs/ffmpeg-kit-8.1-double-execute-crash.md)
- [AddressSanitizer 官方文档](https://github.com/google/sanitizers/wiki/AddressSanitizer)
- [Cppcheck 官方文档](http://cppcheck.sourceforge.net/manual.pdf)
