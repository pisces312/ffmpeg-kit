# FFmpeg 构建总纲（ffmpeg-kit fork / StreamClip）

> **本文是 FFmpeg 构建相关的唯一事实来源**：覆盖两条构建轨道（JNI AAR / CLI 二进制）、全部编译参数、外部依赖库版本、编码器取舍、历史演进与踩坑记录。
> 原先分散在 `ffmpeg-kit/docs/`（6 份）、`D:\workspace`（6 份）、`StreamClip/docs`（1 份）的 13 份构建文档已合并至此并删除（归档备份：`/tmp/ffmpeg-build-docs-merged-20261031.tar.gz`）。
> 本文档自 2026-10-31 起归属 **ffmpeg-kit fork 仓库**（`D:\3rd-party-projects\ffmpeg-kit\docs\`），因为它描述的是本仓库的构建行为，与具体 App 解耦。
> 最后更新：2026-10-31（n8.1.3 重建完成）　当前产物：`ffmpeg-kit-8.1.3.aar`（FFmpeg n8.1.3，12,605,249 B）；上一版 `ffmpeg-kit-8.1.aar`（n8.1，12,625,191 B）已从 StreamClip 仓库移除，可从 commit `ef0d2dc` 取回

---

## 0. 我要做什么 → 看哪节

| 目的 | 章节 |
|---|---|
| 换 FFmpeg 版本、重编 AAR | **§3.8（先看必查清单）**、§3、§8 |
| 查外部库（x264/x265/lame/fdk-aac）版本与升级 | §3.2.1 |
| 改编码器 / 加减组件 | §5、§3.3 |
| 确认某个音频格式是否支持（FLAC/APE/AAC…） | §5.2 |
| 减小体积 | §5.3、§9 |
| 构建报错排错 | §7 |
| 确认某个 .so 是什么版本 | §8.1 |
| 了解为什么走到自编译 | §6 |

---

## 1. 两条构建轨道

| | **A. ffmpeg-kit AAR（主力）** | **B. BinaryFFmpeg（备用）** |
|---|---|---|
| 产物 | `ffmpeg-kit-8.1.3.aar`（12,605,249 B，10 个 `.so`） | `ffmpeg` / `ffprobe` 静态可执行（精简 8.8 MB / 全量 15.2 MB） |
| 调用方式 | Java API `FFmpegKit.executeAsync()`，JNI 进 `libffmpegkit.so` | assets 释放到私有目录 + `Runtime.exec()` |
| FFmpeg 构建形态 | **共享库**（`--enable-shared --disable-static --disable-programs`） | **静态可执行**（`--enable-static --disable-shared`） |
| 进度/取消 | `StatisticsCallback` + `FFmpegKit.cancel(sessionId)`，原生支持 | 正则抓 stdout 的 `time=`，取消靠杀进程 |
| 代码入口 | `FFmpegService.kt` | `BinaryFFmpeg`（Settings 里可切换后端） |
| 当前状态 | 生产路径 | 备用/对比，用于验证 AAR 侧异常 |

两条轨道**共用同一份 FFmpeg 源码树**，只是 configure 不同——所以切换轨道不需要两套源码。注意：二者不能同时存在于同一个构建树（`make distclean` 后重配）。

---

## 2. 环境基线

| 项 | 值 | 说明 |
|---|---|---|
| 宿主 | Windows 11 + **WSL2 Ubuntu** | 必须 WSL：`configure`/`make`/`pkg-config` 是 Unix 工具链，Windows 原生 NDK 的 clang 是 `.exe`，脚本跑不通 |
| NDK | `/home/pisces312/android-ndk-r27d`（27.3.13750724） | Linux 版；轨道 A/B 统一使用（轨道 B 历史上用过 r25b，2026-10-31 合并脚本时统一到 r27d） |
| API level | 24（Android 7.0） | `aarch64-linux-android24-clang` |
| ABI | 仅 `arm64-v8a` | 32 位 ARM 与 x86 全部禁用 |
| FFmpeg 源码 | **`D:\3rd-party-projects\ffmpeg-8.1.3`**（WSL `/mnt/d/3rd-party-projects/ffmpeg-8.1.3`） | 官方 tarball 解压，非 git 仓库；`ffmpeg-kit/src/ffmpeg` 是指向它的相对软链。旧的 `ffmpeg-8.1` 已于 2026-10-31 删除（它是单提交快照，需要时从 ffmpeg.org 重新下载） |
| ffmpeg-kit 工程 | `D:\3rd-party-projects\ffmpeg-kit` | fork `pisces312/ffmpeg-kit` |
| 外部库源码 | `ffmpeg-kit/src/{x264,x265,lame,cpu-features}` | 见 §3.2.0；约 320 MB，未纳入版本库（`src/*` 已 ignore） |
| Android SDK | Windows 侧（WSL 挂载） | Gradle 打包走 `cmd.exe /c gradlew.bat`，因为 build-tools 是 Windows 二进制 |
| JDK | Windows JBR 21（Gradle 用）；WSL 内 JDK 仅供 shell 工具 | 6.0 时代需 JDK 17（Gradle 8.2.1 不支持 21） |

**路径约定（2026-10-31 已固化）**：所有脚本的 `BASEDIR` 改为 `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)`，`pkgconfig/*.pc` 的 `prefix=` 也同步为 `/mnt/d/3rd-party-projects/ffmpeg-kit`。历史上写死的 `/mnt/d/nili/3rd_party_projects/...` 是废弃路径，`pkg-config` 命中它时只会得到空 `-I/-L`，表现为 `x264 not found`。重建前仍建议按 §8.3 抽查一次。

---

## 3. 轨道 A：ffmpeg-kit AAR

### 3.1 三步流水线

| 步 | 脚本 | 输入 | 输出 | 耗时 |
|---|---|---|---|---|
| 1 | `build-ffmpeg-ndk-27d.sh` | `src/{x264,x265,lame}` + FFmpeg 源码 | `prebuilt/android-arm64/ffmpeg/{lib,include}` | 30–50 min（含外部库更久） |
| 2 | `build-jni-ndk-r27d.sh` | `android/jni/Android.mk`（45 个 `fftools_*` + 3 个 JNI 桥） | `libffmpegkit.so`、`libffmpegkit_abidetect.so` | 2–3 min |
| 3 | `build-aar-ndk-r27d.sh` | 上述产物 + Gradle 工程 | `ffmpeg-kit-release.aar` → `llvm-strip` 重打包 | 3–5 min |

脚本约定：外部库与 FFmpeg 都有"存在即跳过"的短路，`FORCE_FFMPEG=1` 强制重编 FFmpeg；`--debug` 参数（步 2/3）保留符号表、跳过 strip，用于 native 崩溃定位。

### 3.2 外部库

#### 3.2.0 源码在哪（构建真正读取的路径）

**有效副本只有 `ffmpeg-kit/src/` 下这一份**，`D:\3rd-party-projects\` 顶层没有 x264/x265 目录（2026-10-31 清理掉了两份冗余克隆，见 §7 #27）。

| 库 | 构建读取路径 | 仓库来源 | 版本 |
|---|---|---|---|
| x264 | `ffmpeg-kit/src/x264`（12 MB） | **`github.com/arthenica/x264`**（arthenica fork，不是 videolan 主干） | stable @ `eaa68fa`（2023-01-28），`X264_BUILD 164` |
| x265 | `ffmpeg-kit/src/x265`（154 MB，含构建产物） | `bitbucket.org/multicoreware/x265_git` | master @ `b81f650`（2026-06-23），`X265_BUILD 216` = 4.2 |
| lame | `ffmpeg-kit/src/lame`（另有 `src/lame-3.100-backup` 回退） | SourceForge lame 4.0 | 4.0 |
| FFmpeg | `ffmpeg-kit/src/ffmpeg` → 相对软链 `../../ffmpeg-8.1.3` | ffmpeg.org n8.1.3 源码包 | n8.1.3 |

证据在脚本里：`build-ffmpeg-ndk-27d.sh` 用 `cd $BASEDIR/src/x264`、`cd $BASEDIR/src/x265/source`，
`FFMPEG_SRC` 默认 `/mnt/d/3rd-party-projects/ffmpeg-8.1.3`。
**换版本 = 直接替换 `src/` 下对应目录**，不要在别处另放一份源码树（两份副本极易编到旧的那份）。

当前产物（**2026-10-31 构建，FFmpeg n8.1.3**）使用的版本：

| 库 | 版本标识 | 静态库 | 关键参数与原因 |
|---|---|---|---|
| **x264** | stable @ `eaa68fa`，`X264_BUILD 164` | `libx264.a` 1,815,426 B | `--enable-pic --enable-static --disable-cli`；`--cross-prefix=$TOOLCHAIN/bin/llvm-`（不是 `aarch64-linux-android-`） |
| **x265** | master @ `b81f650`（2026-06-23），`X265_BUILD 216`（= 4.2） | `libx265.a` 2,656,474 B | `HIGH_BIT_DEPTH=1`（10-bit 能力）、`ENABLE_ASSEMBLY=0`（NDK 交叉编译汇编报 `unknown target CPU 'armv8-a'`，直接关掉）、`ENABLE_SHARED=0`、`STATIC_LINK_CRT=1`、`ENABLE_PIC=1` |
| **lame** | **4.0** | `libmp3lame.a` 342,080 B | `--disable-shared --enable-static --disable-frontend --disable-decoder`；`--disable-decoder` 是 4.0 必需（见 §3.2.2），同时也让体积从 3.100 的 432,658 B 降到 342,080 B |

> 三份历史文档分别写过 x265 为 3.4 / 3.6 / 4.2。**以 `X265_BUILD 216` 为准 = x265 4.2**，`prebuilt/.../pkgconfig/x265.pc` 的 `Version: 4.2` 也印证了这一点。
> 注意区分两套脚本：`scripts/android/*.sh` 是**上游 ffmpeg-kit 脚本，本项目未使用**（里面 `create_x265_package_config "3.4"` 的旧值不必管）；真正执行的是根目录 `build-ffmpeg-ndk-27d.sh`，它内联了三个库的完整构建命令并手写 `x265.pc`。
> **lame 4.0 会生成 `lame.pc`（不是 `mp3lame.pc`）**。历史上 §3 的跳过判据写了 `mp3lame.pc`，该文件从来不存在 → 导致 lame 每次构建都重编；2026-10-31 已改为只看 `libmp3lame.a`。

#### 3.2.1 上游最新版本（2026-10-31 核查）

| 库 | 本地产物 | 上游最新 | 差距 | 升级价值 |
|---|---|---|---|---|
| **x264** | stable @ `eaa68fa`（2023-01-28，BUILD 164） | master @ `c24e06c`（2024-09-17） | 本地落后 master 约 1.6 年；**上游距今天已 2 年零提交** | **很低**。上游实质上已停更；master 增量集中在 LoongArch/checkasm/x86inc 与 MS armasm64 的 SVE 检测，对 arm64 Android 无实际收益 |
| **x265** | **master @ `b81f650`（2026-06-23，BUILD 216）→ 已升级到该版** | master @ `b81f650` | 0 | 已升级（2026-10-31），差 59 提交，其中 `d0137d63 fix: scenecut not active when bframes=0` 与 `-x265-params` 相关 |
| **lame** | **4.0 → 已升级** | **4.0**（2026-07-11） | 0 | 已升级（2026-10-31）。4.0 集中修安全缺陷：AIFF/AIFC `FORM` chunk 尺寸下溢（CVSS 5.5，可致无界自旋 DoS）、`fill_buffer_resample` 边界、以及若干 fuzz 修复。API 完全兼容（`lame_set_VBR_quality` 等签名未变） |
| **fdk-aac** | 未引入 | **3.0.0**（2026-10-11） | — | **可选**。见 §5.2 与 §3.2.2 |

#### 3.2.2 升级到新版本时的构建差异

**lame 4.0 必须加 `--disable-decoder`。** 3.100 里 mpg123 是可选依赖，缺失时静默回退；4.0 改成强制检查，缺失直接 `configure: error: no, libmpg123 not found`。实测（WSL，host gcc）：

```bash
# 失败：报 libmpg123 not found
./configure --disable-frontend --disable-gtktest --with-pic
# 通过：显式关掉 mpg123 解码器（我们只需要编码器）
./configure --disable-frontend --disable-decoder --disable-gtktest --with-pic
```

另外 4.0 的 `configure --help` 已不再列 `--disable-efence` / `--disable-fast-install` / `--disable-maintainer-mode`，但 autoconf 对未识别的 `--disable-*` 仅告警不中断，可保留也可删；`--with-pic` 仍被识别。

**x264 master 与 stable 是分叉关系**（非快进），切 master 需重新验证 arm64 NEON 汇编路径——`common/aarch64/` 与 `common/arm/` 在两者间有 47 个文件、+7241/−2150 行的差异。

**x265 版本号与 `X265_BUILD` 的对应**（实测各 tag）：3.4=**192**、3.5=199、3.6=209、4.0=212、4.1=215、4.2=**216**。本地产物是 216，即 **4.2**。

FFmpeg 的 `libx265.c` 用 `#if X265_BUILD >= 210` 之类条件编译分支，换版本后务必确认走的分支符合预期（n8.1 已覆盖到 216）。`build-ffmpeg-ndk-27d.sh` 里手写的 `x265.pc` 版本已是对的 4.2，但 x265 的 `make install` 本身不产出 pkg-config，替换源码后若删了 `.pc` 需重新手写。

**fdk-aac 3.0.0 的构建**：CMake 与 autotools 双支持（`CMakeLists.txt` + `configure.ac`）。新增独立库 `fdk-xhe-aac`（xHE-AAC 编码），若只要 AAC-LC/HE-AAC 可只链 `fdk-aac`。许可证为 Fraunhofer FDK（非自由），FFmpeg 侧要求 `--enable-nonfree` —— 当前 configure 已带该 flag，可直接启用，但**产物不可再以 LGPL/GPL 单一许可分发**。

### 3.3 FFmpeg configure（产物内嵌的真实参数，47 项）

以下是从 `prebuilt/android-arm64/ffmpeg/include/../config.h` 的 `FFMPEG_CONFIGURATION` 反解出的**发布版实际参数**（`$TOOLCHAIN` = `$NDK/toolchains/llvm/prebuilt/linux-x86_64`）：

```bash
./configure \
  --prefix=$PREFIX --target-os=android --arch=aarch64 --cpu=armv8-a \
  --cc=$TOOLCHAIN/bin/aarch64-linux-android24-clang \
  --cxx=$TOOLCHAIN/bin/aarch64-linux-android24-clang++ \
  --ar=$TOOLCHAIN/bin/llvm-ar --ranlib=$TOOLCHAIN/bin/llvm-ranlib \
  --strip=$TOOLCHAIN/bin/llvm-strip \
  --enable-cross-compile --sysroot=$TOOLCHAIN/sysroot \
  --enable-gpl --enable-nonfree \
  --enable-libx264 --enable-libx265 --enable-libmp3lame \
  --enable-mediacodec --enable-jni \
  --enable-encoder=h264_mediacodec --enable-encoder=hevc_mediacodec \
  --enable-decoder=h264_mediacodec --enable-decoder=hevc_mediacodec \
  --enable-shared --disable-static --disable-doc --disable-programs \
  --extra-cflags="-march=armv8-a -std=c99 -Wno-unused-function -fstrict-aliasing \
      -DANDROID_NDK -fPIC -DANDROID -D__ANDROID__ -D__ANDROID_MIN_SDK_VERSION__=24 \
      -Os -ffunction-sections -fdata-sections -I$PREFIX/include" \
  --extra-ldflags="-L$PREFIX/lib -Wl,--gc-sections -Wl,-z,noexecstack -Wl,-z,relro \
      -Wl,-z,now -Wl,--hash-style=both" \
  --extra-libs="-lm -lc++"
```

分项解释：

| 参数 | 作用 / 为什么必须有 |
|---|---|
| `--sysroot=$TOOLCHAIN/sysroot` | 2026-05-13 那轮重编补上的；缺它会拿到错误系统头 |
| `--enable-gpl --enable-nonfree` | x264/x265 是 GPL，`--enable-nonfree` 让 x265 等非自由组合可链接。**决定了 AAR 只能以 GPL 分发** |
| `--enable-jni` | MediaCodec 硬编解码的必要条件（`libavcodec/jni.h`，运行时通过 `JavaVM` 拿 `AMediaCodec`） |
| `--enable-mediacodec` + 4 条 encoder/decoder | 只显式列 h264/hevc 的硬编硬解；其余 mediacodec 编解码器（av1/vp8/vp9/mpeg2/mpeg4）在默认配置下也存在，但本项目不用 |
| `--enable-shared --disable-static` | AAR 里是 7 个独立 `.so` 而非单体 `libffmpeg.so`；JNI 层动态链接它们 |
| `--disable-programs` | 不产 `ffmpeg`/`ffprobe` 可执行；CLI 由 `fftools_*.c` 在 JNI 里以函数形式复用 |
| `-Os` | 体积优先（全量组件下 `libavcodec.so` 仍有 16 MB） |
| `-fPIC -ffunction-sections -fdata-sections` + `--gc-sections` | 位置无关 + 死代码裁剪 |
| `-Wl,-z,relro -z now --hash-style=both` | Android 加载器兼容 + 加固 |
| `--extra-libs="-lm -lc++"` | x265 是 C++ 库，缺 `-lc++` 时 configure 的链接测试会 `undefined symbol: __cxa_guard_acquire` |

### 3.4 组件覆盖：AAR 是"全量组件"，不是精简清单

**关键事实**：AAR 的 configure **没有** `--disable-everything`。所以除显式开启的外部库与 mediacodec 外，FFmpeg 默认的编码器/解码器/muxer/demuxer/滤镜/协议**全部编入**。

实测抽样（在 `libavcodec.so` 中命中）：`prores_ks` ✅、`mpeg2video` ✅、`v4l2m2m` ✅、`h264_mediacodec` ✅、`libx264/libx265/libmp3lame` ✅；`libvpx_vp9` ❌（未引外部库）。

这解释了两个现象：
- `libavcodec.so` 16 MB、AAR 12.6 MB 的体积来自"全量默认组件"（历史文档里"183 编码器 / 521 解码器"就是这个默认集合的规模）；
- 早期文档列出的"编解码器清单"是**能力清单**（能用什么），不等价于 configure 的 enable 列表。

> 真正按清单裁剪的是轨道 B 的精简版（§4.2）。体积优化应走那条思路，见 §9。

### 3.5 内部头文件回填（必做，否则 JNI 编不过）

`make install` **只安装公开头文件**。JNI 与 `fftools_*` 编译需要 20 个内部头（`config.h`、`libavutil/thread.h`、`libavformat/network.h` 等），必须从源码树回填：

**已脚本化（2026-10-31）**：`build_scripts/backfill_ffmpeg_headers.sh`，构建完 FFmpeg 后直接跑一次：

```bash
./build_scripts/backfill_ffmpeg_headers.sh                    # 默认用 $FFMPEG_SRC
./build_scripts/backfill_ffmpeg_headers.sh /path/to/ffmpeg-src
```

脚本做三件事：建 6 个架构头目录 → 拷 20 个内部头 → **同源断言**：

| 断言 | 期望 |
|---|---|
| `config.h` 含 `mediacodec` | 1 |
| `config.h` 含 `disable-everything` | 0 |
| `config.h` 与构建树 `cmp` 一致 | 相同 |
| `ffversion.h` 版本 | 与源码 `VERSION` 一致 |
| `thread.h` / `internal.h` / `network.h` / `mathops.h` | 存在 |

> 8.1.3 实测：上游已无 `libavutil/x86/emms.h`，脚本会自动跳过并告警，实际回填 19 个。

⚠️ **历史隐患（2026-10-31 已修）**：旧仓库里的 `prebuilt/.../include/config.h` 内容其实是**精简版二进制**的 configure（`--disable-everything`），而 `libavcodec.so` 是 AAR 配置（§3.3）编出来的——**头文件与库不是同一次 configure**。这不只是"理论隐患"：`#if CONFIG_MEDIACODEC` 因此恒为 0，导致 `fftools_ffmpeg.c` 里的 `android_binder_threadpool_init_if_required()` 从未被编译进来（详见 `ffmpeg-modifications.md` #6）。**修正 config.h 后 JNI 链接会立刻报该符号未定义，属预期现象。**

### 3.6 JNI 移植层

上游 `fftools/` 被 flatten + 加 `fftools_` 前缀复制到 `android/ffmpeg-kit-android-lib/src/main/cpp/`，共 **45 个文件**（24 个 flat + `graph/graphprint` 2 + `resources/resman` 2 + `resources/graph.css|html` 生成的 2 + `textformat/` 17）。

| 改造 | 文件 | 内容 |
|---|---|---|
| ① 输出通道迁移 | `fftools_tw_stdout.c` | stdout writer 整体重写为按行 flush 的 avlog writer（ffprobe JSON 才能进 Java） |
| ② 输出通道迁移 | `fftools_opt_common.c` | 103 处 `printf` → `av_log(NULL, AV_LOG_STDERR, ...)`；移除 `av_log_set_callback(log_callback_help)` |
| ③ 输出通道迁移 | `fftools_cmdutils.c`、`fftools_ffmpeg_mux.c` | help/SDP 输出 → stderr / av_log |
| ④ 入口改造 | `fftools_ffmpeg.c`、`fftools_ffprobe.c` | `main()` → `ffmpeg_execute()` / `ffprobe_execute()`；`program_name` 去 `const`（JNI 可写） |
| ⑤ 生命周期修复 | `fftools_ffmpeg.c` | `ffmpeg_cleanup()` 里补 `nb_* = 0` 计数器复位——修「同进程第二次执行 SIGSEGV」 |
| ⑥ 补编 compat | `compat/android/{binder.c,binder.h}` | FFmpeg 8.1.x 的 `compat_objs` 不进 `libav*.so`，需在 JNI 层单独编（见 `ffmpeg-modifications.md` #6） |

其余为纯 include 改名（15 个 basename 加前缀）。`Android.mk` 的 `MY_SRC_FILES` 必须与目录一致（含 `compat/android/binder.c`）；`-Wall -Werror` 编译。

**升级 FFmpeg 版本时不要手工比对**，用三方合并脚本：

```bash
python3 build_scripts/port_fftools.py --new <新版>/fftools --base <旧版>/fftools            # 只报告
python3 build_scripts/port_fftools.py --new <新版>/fftools --base <旧版>/fftools --apply    # 写盘
```

2026-10-31 实测 n8.1→n8.1.3：43 个文件、14 个需处理、**0 冲突**。

### 3.7 AAR 打包与版本号

- Gradle 侧：`android/ffmpeg-kit-android-lib/`，包名 `com.arthenica.ffmpegkit`（8.0 的 `com.antonkarpenko` 分支已弃用）
- 版本号两处：`build.gradle` 的 `versionName "8.1.3"` / `versionCode 240813`；`ffmpegkit.h` 的 `FFMPEG_KIT_VERSION "8.1.3"`
  - `versionCode` 编码规律（由历史值反推）：`24` + `<major 两位>` + `<minor 一位>` + `<patch 一位>`，例：`4.5.1→240451`、`6.0→240600`、`8.1→240810`、`8.1.3→240813`
  - 改 `ffmpegkit.h` 后**必须重跑 `build-jni-ndk-r27d.sh`**，否则版本串不会进 `libffmpegkit.so`
- strip：解压 AAR → `llvm-strip --strip-debug` 逐个 `.so` → 重新 zip
- **Gradle 必须用 JDK 17**：宿主 `JAVA_HOME` 是 `D:\dev\jdk-25`，Gradle 8.10.2 的 Groovy 解析不了 Java 25 字节码（`Unsupported class file major version 69`）。已在 `android/gradle.properties` 固定 `org.gradle.java.home=D:/dev/jdk-17.0.2`
- 接入 StreamClip：`app/build.gradle.kts` 的 `implementation(files("libs/ffmpeg-kit-8.1.3.aar"))`

### 3.8 升级 FFmpeg 后必须重做的本地补丁（checklist）

> ⚠️ **换 FFmpeg 版本的必查项。**
> **上游 `compat/android/binder.c` 里的 `ABinderProcess_setThreadPoolMaxThreadCount(1)` 每次升级都要重新删掉**，
> 否则 App 内第一次执行 ffmpeg 就 `SIGABRT`（`Binder threadpool cannot be shrunk after starting`，见 §7 #20）。
> 这不是 8.1.3 才有的代码——FFmpeg **8.1 就有**，只是我们过去没把它编进 JNI，所以没暴露。
> 换源码树后 `compat/android/binder.c` 会被新文件覆盖，注释和删除都会丢，必须按本表逐条复核。

| # | 项 | 检查命令 | 期望 |
|---|---|---|---|
| 1 | 已删除 `setThreadPoolMaxThreadCount` 调用 | `grep -n setThreadPoolMaxThreadCount android/ffmpeg-kit-android-lib/src/main/cpp/compat/android/binder.c` | **只命中注释**，没有 `dlsym`/函数指针调用 |
| 2 | 编译产物里也没有 | `strings android/libs/arm64-v8a/libffmpegkit.so \| grep -c ABinderProcess_setThreadPoolMaxThreadCount` | `0` |
| 3 | `startThreadPool` 保留 | 同上，`grep -c ABinderProcess_startThreadPool` | `1` |
| 4 | 两份 `binder.c` 只差一行 | `diff $FFMPEG_SRC/compat/android/binder.c .../cpp/compat/android/binder.c` | 唯一差异是 `#include <android/api-level.h>`（`-Werror` 需要） |
| 5 | `MY_SRC_FILES` 含 compat | `grep -c compat/android/binder.c android/jni/Android.mk` | `1` |
| 6 | fftools 三方合并 | `port_fftools.py --new … --base …` | 0 冲突；有冲突必须逐个看 |
| 7 | `ffmpeg_cleanup()` 计数器复位 | `grep -c "nb_.* = 0" .../fftools_ffmpeg.c` | ≥ 5（连续执行不崩的关键） |
| 8 | 输出通道仍是 `av_log` | `grep -cE "[^a-z]printf\(" .../fftools_opt_common.c` | `0` |
| 9 | `APP_PLATFORM` = 24、`src/ffmpeg` 是软链 | `cat android/jni/Application.mk`；`readlink src/ffmpeg` | `android-24`；`../../ffmpeg-8.1.3` |
| 10 | 版本号三处一致 | `ffmpegkit.h` / `build.gradle` 的 `versionName`、`versionCode` | `8.1.3` / `240813`（规律见 §3.7） |
| 11 | AAR 内 `.so` 与源码同代 | `./check-aar-ffmpeg-version.sh <aar>` | `8.1.3` + `LIBAVUTIL_60` |

第 1、2 条是**硬门槛**：只要有一处残留，装到手机上压缩任何视频都会闪退，且崩在 `ffmpeg_execute` 里，看起来像"FFmpeg 本身的问题"。

---

## 4. 轨道 B：CLI 二进制

脚本位置：**`build-cli-binary-ndk-r27d.sh`**（仓库根目录，双模式：`full` / `minimal`，默认 `minimal`）。

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit
./build-cli-binary-ndk-r27d.sh minimal      # 8.8 MB，按清单裁剪
./build-cli-binary-ndk-r27d.sh full         # 15.2 MB，全量组件
```

产出落在 `out/cli/{minimal,full}/bin/`，**不写 `prebuilt/`**（那是轨道 A 的目录）。

> 本节内容来自原先散落在 `D:\workspace\ffmpeg-8.1-android-bin\` 的两个脚本（`build_ffmpeg_android.sh` / `build_minimal.sh`，2026-05-11），已合并为上述单一脚本并删除原件。
> 同目录下的 `configure_options.txt` 只是 `./configure --help` 的 310 行输出（通用选项说明，与本次构建参数无关），无保留价值，未迁移。

**合并时修正的三个问题**（原脚本直接跑会失败或产物错位）：

| 问题 | 原状 | 修正 |
|---|---|---|
| NDK 版本 | 写死 `android-ndk-r25b` | 统一到 `r27d`，与轨道 A 一致 |
| 路径 | 写死 `/home/pisces312/ffmpeg-8.1`、`/home/pisces312/android_build/...` | 仓库根由 `BASH_SOURCE` 自动推导；源码目录可用 `FFMPEG_SRC` 覆盖 |
| `PKG_CONFIG_PATH` | 指向**自己的输出目录**（空目录）→ `--enable-libx264/libx265` 必然 `not found` | 指向 `prebuilt/android-arm64/ffmpeg/lib/pkgconfig`（轨道 A 的 arm64 静态库） |

**执行顺序约束**：本脚本默认原地构建，开头会 `make distclean`，会清掉轨道 A 的 `config.h`。推荐 **先 AAR 后 CLI**；若之后要重建 AAR，需重跑 `build-ffmpeg-ndk-27d.sh` 重新 configure。

### 4.1 全量版（`full` 模式）

```bash
./configure --prefix=$PREFIX --target-os=android --arch=aarch64 --cpu=armv8-a \
  --cc=$CC --cxx=$CXX --strip=$STRIP --enable-cross-compile \
  --disable-debug --enable-static --disable-shared --enable-small \
  --enable-gpl --enable-nonfree --enable-neon \
  --disable-doc --disable-ffplay \
  --extra-cflags="-O3 -Wall -fPIE -fPIC" --extra-ldflags="-pie -static"
```

- 规模：183 编码器 / 521 解码器 / 542 muxer / 359 demuxer / 477 滤镜 / 30 协议
- 体积：`ffmpeg` 15.2 MB、`ffprobe` 15.1 MB
- `--strip` 必须指 `llvm-strip`（NDK 无 `aarch64-linux-android-strip`）

### 4.2 精简版（`minimal` 模式，默认）

在 `--disable-everything` 基础上按清单启用（8.8 / 8.6 MB，比全量小 42%）：

| 类别 | 启用项 |
|---|---|
| 编码器 | `libx264, libx265, h264_v4l2m2m, aac` |
| 解码器 | `h264, hevc, h264_v4l2m2m, hevc_v4l2m2m, aac, aac_latm, mp3, mp3float` |
| muxer / demuxer | `mp4, mov, matroska, avi, flv` |
| 滤镜 | `scale, crop, trim, concat, volume, fade, rotate, transpose, overlay, format, fps, afade, acrossfade, aformat, atrim, volumedetect, cropdetect` |
| 协议 | `file` |
| BSF | `h264_mp4toannexb, hevc_mp4toannexb, aac_adtstoasc` |
| parser | `h264, hevc, aac, mpegaudio` |

### 4.3 为什么二进制版不用 mediacodec

静态可执行文件无法在运行时通过 JNI 拿到 `AMediaCodec`（需要 `JavaVM`），这就是精简版里只能写 `h264_v4l2m2m` 而**实际不可用**的原因——Android 没有 V4L2 M2M 设备节点。**硬编能力只有轨道 A 有**，这是保留 AAR 为主力的根本原因。

---

## 5. 编码器/组件决策矩阵

### 5.1 视频

| 组件 | 类型 | AAR | Binary | 用途与理由 |
|---|---|---|---|---|
| `h264_mediacodec` | 硬编 | ✅ | ❌ | 压缩页默认（H.264 硬编），速度快、发热低 |
| `hevc_mediacodec` | 硬编 | ✅ | ❌ | 压缩页 H.265 硬编 |
| `libx264` | 软编 GPL | ✅ | ✅ | 硬编不可用/画质优先时的回退；`-crf` 可控 |
| `libx265` | 软编 GPL | ✅ | ✅ | 同上，HEVC 软编 |
| `h264` / `hevc` 解码 | 软解 | ✅（默认集） | ✅ | ffprobe、波形、缩略图路径；硬解失败时兜底 |
| `h264_mediacodec` / `hevc_mediacodec` 解码 | 硬解 | ✅ | ❌ | 大分辨率素材解码加速 |
| `h264_v4l2m2m` / `hevc_v4l2m2m` | 硬编 | ✅（默认集） | ✅（已启） | **实测不可用**：Android 无 V4L2 M2M 节点。保留仅为历史兼容 |
| `prores_ks` / `mpeg2video` / `mpeg4` 等 | 软编 | ✅（默认集带入） | ❌ | 未使用，属于"没裁掉"的默认组件 |
| AV1（`libaom`/`svt`） | 软编 | ❌ | ❌ | 未引外部库；AV1 只经 mediacodec 且本项目不做 AV1 输出 |
| VP8/VP9（`libvpx`） | 软编 | ❌ | ❌ | 未引外部库；WebM 输出不在产品范围 |

### 5.2 音频

| 组件 | AAR | Binary | 说明 |
|---|---|---|---|
| `aac`（内置） | ✅ | ✅ | 音频压缩默认编码器（`AudioEncoder.kt:187`）。**编解码器跟随 FFmpeg 版本**，n8.1→n9.0 的 aacenc 改动集中在多声道 PCE/通道布局（7.1、6.1、FLC/FRC），立体声无变化 |
| `libmp3lame` | ✅ | ❌ | MP3 导出（`AudioEncoder.kt:176`）+ `AudioCompressFragment` 的 mp3 分支 |
| `flac`（内置） | ✅ | ❌ | 无损音频导出（`AudioEncoder.kt:184`）。**FFmpeg 自带原生 FLAC 编码器**，不需要外部 `libFLAC`，也无版本跟随问题 |
| `pcm_s16le` | ✅ | ❌ | WAV 导出（`AudioEncoder.kt:196`） |
| `opus`（内置，实验性） | ✅ | ❌ | **已决定走这条路（2026-10-31，决策 B）**：不重编，`AudioEncoder.kt` 改用内置编码器。三条硬约束——① 必须 `-strict -2`（`AV_CODEC_CAP_EXPERIMENTAL`，否则 `Error while opening encoder`）；② 只接受 48000/24000/16000/12000/8000，且**不像 libopus wrapper 那样内部重采样**，显式 `-ar 44100` 会直接失败，故代码强制 `-ar 48000`；③ 没有 `-vbr` 选项（libopus wrapper 私有），只能给 `-b:a`，编码器本身恒 VBR，CBR/VBR 两档输出一致 |
| `libopus` | ❌ | ❌ | **未引入（已放弃）**：原 `AudioEncoder.kt:199` 写 `-c:a libopus` 但 configure 无 `--enable-libopus`，报 `Unknown encoder 'libopus'`。加库需重编 FFmpeg 30–50 min + AAR 增长约 0.5 MB，因 Opus 使用频率低，改为使用上面的内置编码器 |
| `libfdk_aac` | ❌ | ❌ | **未引入**。FFmpeg 之外质量最好的 AAC 编码器（低码率优势明显），上游 3.0.0 于 2026-10-11 发布，新增 xHE-AAC 库。代价：+约 2 MB、`--enable-nonfree`、且 Fraunhofer 许可与 GPL 冲突 |
| `libopencore-amrnb` | ❌ | ❌ | 早期第三方 full 包有，自编译 AAR 从未启用（`strings` 无命中） |

#### 5.2.1 APE / FLAC 的支持边界

| 格式 | 编码 | 解码 | 结论 |
|---|---|---|---|
| **FLAC** | ✅ 内置 `flac` 编码器 | ✅ | 无损导出可用，无需任何外部库 |
| **APE**（Monkey's Audio） | ❌ **不存在编码器** | ✅ `ape` 解码器 | FFmpeg 至今**没有** APE 编码器（`libavcodec/apeenc.c` 不存在，`allcodecs.c` 只有 decoder 注册）。APE 只能作为**输入源**被转码，无法作为导出格式。要支持 APE 输出只能引第三方 `mac`（Monkey's Audio SDK），属净新增工作量，不建议 |

> 与此同类的还有：WavPack 有编解码、TTA 有编解码、ALAC 有编解码（均在默认集内）——如果产品需要"无损导出"的多种选择，这些是零成本可用的；APE 是唯一只有解码没有编码的主流无损格式。

### 5.3 容器 / BSF / 协议 / 滤镜

| 类别 | AAR | 说明 |
|---|---|---|
| muxer | 全量（默认集） | 实际使用 `mp4`、`mov`（GPS 需 `-f mov`，见 §7）、`matroska`、`m4a`、`mp3`、`flac`、`wav`、`mpegts`（合并中间格式） |
| demuxer | 全量（默认集） | 实际使用 `mp4/mov`、`matroska`、`avi`、`flv`、`concat`、`image2` |
| BSF | 全量（默认集） | 必需：`h264_mp4toannexb`、`hevc_mp4toannexb`（TS 合并）、`aac_adtstoasc` |
| 协议 | 全量（默认集） | 实际只用 `file`；含 `http/tcp/udp/rtmp` 等属于默认集冗余 |
| 滤镜 | 全量（默认集） | 实际使用 `scale`、`crop`、`trim`、`concat`、`overlay`、`format`、`fps`、`rotate/transpose`、`volume`、`afade/acrossfade`、`aformat/atrim`、`volumedetect`、`cropdetect`、`astats/ametadata`（波形） |

> 由此得出一条裁剪结论：**AAR 至少需要全集里的 muxer/demuxer/BSF/parser 才能安全**（用户可自定义命令），可裁的主要是**未使用的编码器与协议**，粗估能砍 30–40% 体积。这条路尚未走过，见 §9。

---

## 6. 演进史

| 阶段 | 时间 | 来源 | AAR/产物 | 关键事件 |
|---|---|---|---|---|
| 0 | ~2026-04 | 第三方预构建 `ffmpeg-kit-full-gpl` | — | App 用 `assets` 里的 ffmpeg 二进制 + `ProcessBuilder` |
| 1 | 2026-04-30 | `arthenica/ffmpeg-kit` **v6.0** 自编 | 6.8 MB | `android.sh --disable-arm-v7a ... --enable-android-media-codec --enable-android-zlib`，JDK 17 + NDK r25b；App 改走 JNI API |
| 2 | ~2026-05 | `antonkarpenko/ffmpeg-kit` **8.0.0** 预构建 | — | 包名变 `com.antonkarpenko.ffmpegkit`、`failStackTrace` 被移除、smart-exception 依赖删除；仅改 2 个文件 |
| 3 | 2026-05-10 | 自建 **Binary** 轨道 | 15.2 / 8.8 MB | 静态 `ffmpeg`/`ffprobe`，NDK r25b，先全量后精简 |
| 4 | 2026-05-13 | 自编 **FFmpeg 8.1 + ffmpeg-kit 8.1** | 12.1 MB | 起因：H.265 硬编 + AAC 时 `libswresample.so` NEON 崩溃 → 补齐 `-march=armv8-a`/`--sysroot` 等参数重编；同轮加 `FORCE_FFMPEG` |
| 5 | 2026-05-14 | 同上 + SDK r27d | 12.6 MB | 修「同进程二次执行 SIGSEGV」（`ffmpeg_cleanup` 计数器复位）；`build-*-ndk-r27d.sh` 三脚本成型 |
| 6 | 2026-10-31 | n8.1.3 + 外部库升级 | 12.6 MB | FFmpeg 8.1 → 8.1.3；lame 3.100→4.0、x265 追平 master `b81f650`。**首次把 `compat/android/binder.c` 编进 JNI**，引出"App 内必崩"的 `setThreadPoolMaxThreadCount` 回归（§7 #20），现已修 |

---

## 7. 踩坑登记（按发生顺序去重）

| # | 现象 | 根因 | 解决 |
|---|---|---|---|
| 1 | `cpu-features: failed` | 用了 Windows 版 NDK | WSL 内装 **Linux 版** NDK |
| 2 | Docker 编译卡死 | WSL2 嵌套虚拟化 | 放弃 Docker，`apt` 装依赖原生编译 |
| 3 | `git clone` 被 SIGKILL | WSL2 内存限制 | `--depth=1` 或 Windows 侧下 ZIP |
| 4 | `core-for-system-modules.jar` transform 失败 | Gradle 8.2.1 不支持 JDK 21 | 降到 JDK 17（6.0 时代） |
| 5 | `pkg-config: command not found` | WSL 缺包 | 脚本自建 wrapper 到 `/usr/local/bin/pkg-config` |
| 6 | `x265 not found using pkg-config` | x265 的 cmake install **不生成** `x265.pc`；生成的 `Libs.private` 还是坏的（`-l-l:libunwind.a`） | 手写 `x265.pc`，依赖放 `Libs` 行 |
| 7 | `undefined symbol: log / exp / __cxa_guard_acquire` | configure 链接测试缺数学库与 C++ 运行时 | `--extra-libs="-lm -lc++"` |
| 8 | NEON 路径崩溃（`libswresample`） | 缺 `-march=armv8-a`、`--sysroot` 等 Android arm64 参数 | 外部库与 FFmpeg 全部补参后重编 |
| 9 | `'config.h' file not found` / `libavutil/thread.h` | `make install` 不装内部头 | §3.5 回填 20 个头 |
| 10 | `LOCAL_SRC_FILES points to a missing file`（cpu-features） | 清理时误删 `prebuilt/android-arm64/cpu-features/` | 从备份恢复，**不可删** |
| 11 | `Module ffmpegkit depends on undefined modules: c++_shared` | NDK r27d 依赖检查更严 | `ndk-build ... APP_ALLOW_MISSING_DEPS=true` |
| 12 | `aarch64-linux-android-strip: not found` | r25b 起改用 LLVM 工具链 | `--strip=$TOOLCHAIN/bin/llvm-strip` |
| 13 | WSL 里跑不了 Gradle | build-tools 是 Windows 二进制 | `cmd.exe /c gradlew.bat` |
| 14 | 脚本报 `$'\r': command not found` | Windows 编辑产生 CRLF | `sed -i 's/\r$//' *.sh` |
| 15 | 压缩后图库读不到 GPS | FFmpeg 的 mp4 模式写 Apple `loci` 原子，Android 只认 `xyz` | 输出强制 `-f mov` |
| 16 | HEVC 合并报错 | 硬编码了 `h264_mp4toannexb` | 先 `FFprobeKit` 探编码再选 `hevc_mp4toannexb` |
| 17 | 同进程第二次执行崩溃 | `ffmpeg_cleanup()` 释放数组但不清 `nb_*` 计数 | `fftools_ffmpeg.c` 里补 4 个 `nb_* = 0` |
| 18 | `-display_rotation` 报 "cannot be applied to output url" | 它是 **输入** 选项（`OPT_INPUT`），必须在 `-i` 之前 | 移到 `-i` 前（另见 `rotation-design.md`） |
| 19 | AAR 里 `config.h` 与实际 `.so` 的 configure 不一致 | 回填时用错版本（§3.5 隐患） | 回填后 grep 校验 `FFMPEG_CONFIGURATION` |
| 20 | **App 内每次执行 ffmpeg 都 SIGABRT**：`Abort message: 'Binder threadpool cannot be shrunk after starting'`，栈顶 `setThreadPoolMaxThreadCount` ← `ABinderProcess_setThreadPoolMaxThreadCount` ← `android_binder_threadpool_init_if_required` ← `ffmpeg_execute` | 上游 `compat/android/binder.c` 会调 `ABinderProcess_setThreadPoolMaxThreadCount(1)`；该断言要求 `mThreadPoolStarted` 时上限不得变小。**App 进程里 ART 早已启动 binder 池且上限更高**，传 1 = 缩容 → `LOG_ALWAYS_FATAL`。上游代码面向 ffmpeg 独立可执行文件，嵌入 App 场景不成立。旧 8.1 AAR 没编这段，故无此问题 | 删掉该调用，只保留幂等的 `startThreadPool()`；见 `ffmpeg-modifications.md` #6、§3.8 |
| 21 | JNI 链接报 `undefined symbol: android_binder_threadpool_init_if_required`（**修好 config.h 同源后才出现**） | FFmpeg 的 `compat_objs` 只链进可执行文件，我们 `--disable-programs` 所以 6 个 `libav*.so` 里都没有；而 `CONFIG_MEDIACODEC=1` 后 `fftools_ffmpeg.c` 会调它 | 把上游 `compat/android/{binder.c,binder.h}` 镜像到 `cpp/compat/android/`，`Android.mk` 的 `MY_SRC_FILES` 追加 |
| 22 | `-Werror,-Wunused-function`（binder 相关静态函数"未使用"） | `APP_PLATFORM` 仍是 `android-21`，`#if __ANDROID_API__ >= 24` 分支被预处理掉 | `APP_PLATFORM := android-24`；同文件删掉 `-DFFMPEG_KIT_LTS`（会让 `isNativeLTSBuild()` 错报 true） |
| 23 | Gradle 报 `Unsupported class file major version 69` | 宿主 `JAVA_HOME` 是 JDK 25，Gradle 8.10.2 的 Groovy 解析不了 | `android/gradle.properties` 固定 `org.gradle.java.home=D:/dev/jdk-17.0.2` |
| 24 | lame 每次都重编（`already built` 判定从不命中） | 跳过判据查 `$PREFIX/lib/pkgconfig/mp3lame.pc`，而 lame 实际生成的是 `lame.pc` | 判据改为 `$PREFIX/lib/libmp3lame.a` |
| 25 | lame 4.0 `configure: error: no, libmpg123 not found` | 4.0 把 mpg123 从可选依赖改成强制检查 | 加 `--disable-decoder`（只要编码器） |
| 26 | 在别的目录跑脚本就报 `$BASEDIR 不像 ffmpeg-kit 仓库根` / `x264 not found` | `BASEDIR` 写死旧路径 `/mnt/d/nili/3rd_party_projects/...`，`.pc` 的 `prefix=` 同样过期 | `BASEDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)`；`.pc` 前缀改 `/mnt/d/3rd-party-projects/ffmpeg-kit` |
| 27 | 想拿 `ffmpeg-8.1` 当升级基线，发现版本对不上 | 那份是**单提交快照**（`git log` 只有 `init`，无 remote/tag），且混入了 `config.h`/`.o` 等构建产物 | 8.1.3 改用官方 tarball 重新解压；今后升级基线一律现下 `ffmpeg-<ver>.tar.xz`，不复用构建树 |
| 28 | `src/ffmpeg` 占 118 MB 却版本不明 | 是 `cp -r` 出来的僵尸副本，不是软链 | 改为相对软链 `../../ffmpeg-8.1.3`（`port_fftools.py` 与脚本都按 `$FFMPEG_SRC` 取源码） |

---

## 8. 校验与排错

### 8.1 版本 ↔ SONAME 对照（判断 .so 是哪代 FFmpeg）

| FFmpeg | libavutil MAJOR | libavcodec MAJOR | libavformat MAJOR |
|---|---|---|---|
| 5.x | 57 | 59 | 59 |
| 6.x | 58 | 60 | 60 |
| 7.x | 59 | 61 | 61 |
| **8.x** | **60** | **62** | **62** |
| 9.x | 61 | 63 | 63 |

当前 AAR 实测：`LIBAVUTIL_60` / `LIBAVCODEC_62` / `LIBAVFORMAT_62` → **FFmpeg 8.x**（8.1 与 8.1.3 的 SONAME 完全相同，靠版本字面量区分，见下一条）。

> **8.1 与 8.1.3 的 `.so` 只差版本串**：`libavutil.so` 内 `8.1` → `8.1.3`，SONAME 节点仍是 `LIBAVUTIL_60`。
> 所以"是不是新 AAR"不能看 SONAME，要看版本字面量或 configure 里的 `--prefix`（编译路径指纹）。

### 8.2 产物校验命令

```bash
# 版本（注意：strings 默认最小长度是 4，"8.1" 会被直接漏掉，必须显式 -n 3）
grep FFMPEG_VERSION prebuilt/android-arm64/ffmpeg/include/libavutil/ffversion.h   # "8.1.3"
strings -n 3 prebuilt/android-arm64/ffmpeg/lib/libavutil.so | grep -E '^8\.1(\.[0-9])?$'

# SONAME / 依赖
readelf -d prebuilt/android-arm64/ffmpeg/lib/libavutil.so | grep -E 'SONAME|NEEDED'

# 能力抽查（确认 mediacodec / x264 / x265 在）
strings prebuilt/android-arm64/ffmpeg/lib/libavcodec.so | grep -c mediacodec      # 期望 >0
strings prebuilt/android-arm64/ffmpeg/lib/libavcodec.so | grep -x libx265         # 期望 1

# config.h 与库是否同源（§3.5 隐患）
grep -o 'FFMPEG_CONFIGURATION ".*' prebuilt/android-arm64/ffmpeg/include/config.h | grep -c mediacodec

# binder 补丁是否生效（§3.8 硬门槛）
strings android/libs/arm64-v8a/libffmpegkit.so | grep -c ABinderProcess_setThreadPoolMaxThreadCount  # 期望 0
strings android/libs/arm64-v8a/libffmpegkit.so | grep -c ABinderProcess_startThreadPool              # 期望 1

# AAR
unzip -l app/libs/ffmpeg-kit-8.1.3.aar | grep '\.so$'      # 期望 10 行
./check-aar-ffmpeg-version.sh app/libs/ffmpeg-kit-8.1.3.aar
```

> 本机 WSL 若 `strings` 不在 PATH（沙箱裁过 PATH 时会出现），用 `llvm-strings`（NDK 自带）或
> `grep -a` 代替；`grep -a 'ABinderProcess_setThreadPoolMaxThreadCount' binary` 同样有效。

### 8.3 重建前自检清单

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit
grep -n "BASEDIR=\|FFMPEG_SRC=" build-*.sh          # 必须是 /mnt/d/3rd-party-projects/...
grep -h '^prefix=' prebuilt/android-arm64/ffmpeg/lib/pkgconfig/*.pc   # 同上
ls prebuilt/android-arm64/cpu-features/lib/libndk_compat.a          # 存在
ls prebuilt/android-arm64/ffmpeg/include/libavutil/thread.h          # 存在
readlink src/ffmpeg                                                  # ../../ffmpeg-8.1.3
# ★ 换了 FFmpeg 源码树之后，这一步必做（详见 §3.8）
grep -n setThreadPoolMaxThreadCount \
  android/ffmpeg-kit-android-lib/src/main/cpp/compat/android/binder.c  # 只应命中注释
```

> 顺序提醒：**先 AAR 后 CLI**。`build-cli-binary-ndk-r27d.sh` 会 `make distclean`，把轨道 A 的
> `config.h` 一起清掉，回头再编 AAR 就得重来。

### 8.4 调试构建

`build-jni-ndk-r27d.sh --debug` → `Application.mk` 临时改 `APP_OPTIM := debug` / `-O3`→`-O0 -g`；
`build-aar-ndk-r27d.sh --debug` → 跳过 strip，保留符号表。两者都会在结束时恢复/跳过，适合 native 崩溃抓栈。

---

## 9. 待办与优化方向

**已完成（2026-10-31）**

| 项 | 结果 |
|---|---|
| 外部依赖库升级 | lame 3.100 → **4.0**；x265 → master `b81f650`；x264 保持 stable（上游已停更，升级无收益） |
| 内部头回填脚本化 | `build_scripts/backfill_ffmpeg_headers.sh`，含 5 条同源断言 |
| fftools 移植脚本化 | `build_scripts/port_fftools.py`，n8.1→n8.1.3 实测 43 文件 / 0 冲突 |
| `Application.mk` 清理 | `APP_PLATFORM := android-24`；删掉 `-DFFMPEG_KIT_LTS` |
| `libopus` 缺口 | 决策 **B**：不重编，改用内置 `opus -strict -2` + 强制 48 kHz（详见 §5.2 与 StreamClip `AudioEncoder.kt`） |
| binder 回归 | 已修（§7 #20），并写成 §3.8 的升级必查项 |

**仍待办**

1. **真机回归未跑满**：安装、4K 硬编、ffprobe 元信息 JSON、help/错误输出、连续执行 10 次不崩 —— 其中压缩与 ffprobe 已在真机验证过，其余项建议随下个版本补测。
2. **体积优化（独立立项）**：`libavcodec.so` 16 MB / AAR 12.6 MB 来自默认全量组件。按 §5.3 结论，裁掉未使用的编码器与协议预计可降 30–40%，需配套自定义命令的可用性回归。
3. **第三方库版本清单**：`src/{x264,x265,lame}` 是手工放置的源码目录，没有版本记录，已出现"目录里是 x265 4.2、pkg-config 写 3.4"的漂移。建议加 `scripts/android/versions.conf`（仓库 URL + commit + `X264_BUILD`/`X265_BUILD`），构建时断言。§3.2.0 的表格可作为初始值。

---

## 附录：相关文档导航

**本仓库（ffmpeg-kit fork）**

| 文档 | 内容 |
|---|---|
| [ffmpeg-modifications.md](ffmpeg-modifications.md) | 对 FFmpeg 源码做的全部修改（fftools 移植层改造） |
| [ffmpeg-8.1.3-rebuild-plan.md](ffmpeg-8.1.3-rebuild-plan.md) | 8.1.3 重建施工方案（含外部库升级决策） |
| [native-memory-check-guide.md](native-memory-check-guide.md) | 原生内存检查流程 |

**StreamClip 仓库（`D:\my-projects\StreamClip\docs`）**

| 文档 | 内容 |
|---|---|
| `ffmpeg9-upgrade-assessment.md` | 为何不升 FFmpeg 9.0（评估与证据链） |
| `native-video-compress-design.md` | 压缩页设计（编码器选择的产品侧逻辑） |
| `rotation-design.md` | 旋转元数据方案（含 `-display_rotation` 位置坑） |
| `ffmpeg-kit-8.1-double-execute-crash.md` / `ffmpeg-8.1-consecutive-crash-analysis.md` | 二次执行崩溃分析 |
| `aac-crash-analysis.md` / `swresample-crash-analysis.md` | 音频相关崩溃根因 |

**外部**

| 路径 | 内容 |
|---|---|
| `../../build-cli-binary-ndk-r27d.sh` | 轨道 B 的构建脚本（仓库根，`full` / `minimal` 双模式） |
| `D:\workspace\article-ffmpeg-android-cross-compile.md` | 对外发布版教程（叙事化，含相同事实） |
