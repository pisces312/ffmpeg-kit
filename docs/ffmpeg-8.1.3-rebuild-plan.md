# FFmpeg 8.1.3 重建方案（ffmpeg-kit AAR）

> **决策**：采纳 **8.1.3 补丁级升级**，不跳 FFmpeg 9.0。
> 依据见 StreamClip 仓库的 `docs/ffmpeg9-upgrade-assessment.md`（9.0 对本项目零功能收益，且 movenc 时间基变更带来回归风险；8.1.3 已拿齐 9.0 的 mov 解封装安全加固）。
> **前置阅读**：[`ffmpeg-build.md`](ffmpeg-build.md) —— 构建总纲（环境基线、完整 configure 参数、外部库版本、编码器取舍、踩坑登记）。本文只写 8.1.3 相对 8.1 的**增量改动**，通用背景不重复。
> 编写日期：2026-10-31　最后更新：2026-10-31（补充 D2–D5 外部库决策）　适用：`D:\3rd-party-projects\ffmpeg-kit` fork

---

## 0. 目标与不变项

| 项 | 内容 |
|---|---|
| 交付物 | `ffmpeg-kit-8.1.3.aar`（arm64-v8a，GPL，含 libx264 / libx265 / libmp3lame / MediaCodec） |
| 变更 A | libav* 由 n8.1 → n8.1.3（508 个上游提交）；JNI 移植层同步 7 个 fftools 文件 |
| 变更 B | 外部依赖库：**lame 3.100 → 4.0**、x265 追平上游 master、x264 维持现状（见 D2–D5） |
| 不变 | Java/Kotlin API、包名 `com.arthenica.ffmpegkit`、ABI（arm64-v8a）、configure 选项（新增项除外）、`Mp4RotationUtils` workaround |
| 尺寸预期 | AAR 基线 12,625,191 B；FFmpeg 升级与 lame 4.0 合计允许 +8%（≈13.6 MB），超出需单独排查 |

### 决策总览

| 编号 | 议题 | 结论 | 对构建的影响 |
|---|---|---|---|
| D1 | `libopus` 缺口 | **已定：改内置 `opus -strict -2` + 强制 48 kHz（D1-b）** | 不动构建 |
| D2 | x264 是否升到 master | **不升**，维持 stable `eaa68fa` | 不动构建 |
| D3 | x265 是否追平上游 | **升**到 master `b81f650`（4.2 + 59 提交） | 重编 libx265.a |
| D4 | lame 是否升 4.0 | **升**（安全修复），必须加 `--disable-decoder` | 重编 libmp3lame.a |
| D5 | 是否引入 fdk-aac 3.0.0 | **暂不引入**，留作独立评估 | 不动构建 |

---

### D1 待决策：`libopus` 缺口怎么办

`AudioEncoder.kt:199` 在 Opus 导出分支写的是 `-c:a libopus`，但 configure 从未 `--enable-libopus`，产物里也没有该编码器 → 这个导出选项当前**必然失败**（`Unknown encoder 'libopus'`）。

| 选项 | 做法 | 代价 | 建议 |
|---|---|---|---|
| D1-a | 8.1.3 顺带编入 `libopus` | 新增外部库源码 + configure 两项 + 回归；AAR 增约 200–300 KB | 若 Opus 导出是产品功能，选这个 |
| D1-b | 改成 FFmpeg 内置 `opus`（`-strict -2`） | 零构建改动，画质/码率控制略弱，实验性标记 | 若只作"有损导出"兜底，选这个 |
| D1-c | 从 UI 移除 Opus 选项 | 零改动，功能回退 | 若确认无人用 |

**已定案（2026-10-31）：走 D1-b，不重编。** `AudioEncoder.kt` 的 Opus 分支改为 `-ar 48000 -c:a opus -strict -2 -b:a <bps>`，并删掉 `-vbr on/off`（内置编码器无此选项）。Desktop ffmpeg 实测：不加 `-strict -2` → `Error while opening encoder`；显式 `-ar 44100` → 同样失败（内置编码器不做内部重采样），故必须强制 48 kHz。若日后 Opus 升级为常用格式，再翻 D1-a。该决策与 8.1.3 本体无耦合。

---

### D2 决策：x264 —— 不升

| 事实 | 数据 |
|---|---|
| 本地产物 | stable @ `eaa68fa`（2023-01-28），`X264_BUILD 164` |
| 上游最新 | master @ `c24e06c`（**2024-09-17**，此后零提交）；stable @ `b35605a`（2023-10-01） |
| 差距性质 | **非快进**：master 与 stable 分叉，`common/aarch64/` + `common/arm/` 47 文件 +7241/−2150 行 |
| 增量内容 | LoongArch LASX 优化、checkasm 重构、x86inc ELF PIC 改进、MS armasm64 的 SVE 检测 |
| 对 arm64 Android 的收益 | **≈0**。没有 NEON 核心函数重写，SVE 那条只针对 Windows on ARM 的汇编器 |

**结论**：x264 上游已实质停更（2 年零提交），"用最新源码"没有可换的东西。切 master 反而要重验 arm64 汇编、承担分叉风险。保持 stable `eaa68fa` 不动。

> 若坚持要动，唯一合理动作是把 stable 从 `eaa68fa` 快进到 `b35605a`（2023-10-01，含 ppc 编译修复 + qpfile 解析加固），对 arm64 无行为变化，属"顺手对齐"。

---

### D3 决策：x265 —— 追平上游 master

| 事实 | 数据 |
|---|---|
| 本地产物 | master @ `7b3d1f5`（2026-05-04），`X265_BUILD 216`（= 4.2） |
| 上游最新 | master @ `b81f650`（2026-06-23），4.2 tag 之后 59 个提交 |
| 相关修复 | `d0137d63 fix: scenecut not active when bframes = 0`、`97682a8b Fix build warning`、ARM/NEON 若干 |
| 其余 | LoongArch64 blockcopy/mc/intrapred 优化、PowerPC64 CMake 修复 |

**结论**：升。改动小、风险低（仍是同一条 master 线，非分支切换），且 `scenecut + bframes=0` 是真实编码行为修复。

**替换源码后的检查点**：

1. **`X265_BUILD` 不变（实测：本地 `7b3d1f5`、4.2 tag、上游最新 `b81f650` 三者都是 216）** → API 未变，`libavcodec/libx265.c` 的条件编译分支、`x265.pc` 的 `Version: 4.2` 都不用动。这是 D3 风险低的核心原因。
2. 实际构建脚本 `build-ffmpeg-ndk-27d.sh` 里手写的 `x265.pc` 已是 `Version: 4.2`（与产物的 `prebuilt/.../pkgconfig/x265.pc` 一致），**不需要改**。
3. 上游脚本 `scripts/android/x265.sh` 里的 `create_x265_package_config "3.4"` 是旧值，但本项目不使用该脚本，可顺手同步为 4.2，不改也不影响构建。

---

### D4 决策：lame —— 升 4.0（本次外部库升级的重点）

| 事实 | 数据 |
|---|---|
| 本地产物 | 3.100（2017-10） |
| 上游最新 | **4.0（2026-07-11）**，包体 1,496,810 B |
| 变更性质 | 安全与健壮性为主 + 少量 fuzz 修复 |
| API 兼容 | ✅ `lame_set_VBR_quality` / `lame_init` / `lame_encode_buffer_interleaved` 全部保留 |

4.0 的实质修复（摘自 ChangeLog）：

| 提交 | 问题 | 影响面 |
|---|---|---|
| `2026-07-11` frontend/get_audio.c | AIFF/AIFC 的 `FORM` chunk 尺寸 < 4 时无符号下溢，回绕到约 4GB → 无界自旋 | CVSS 5.5 本地 DoS；**只影响 CLI frontend**（我们 `--disable-frontend`，不触发） |
| `2026-07-11` libmp3lame/util.c | `fill_buffer_resample()` 的 `blackfilt[joff]` 索引只在 `assert` 下受保护（NDEBUG 编译时消失） | 论证为构造上有界，属**注释澄清**而非行为改动 |
| 其余 | 若干 fuzz 与构建修复 | 低风险 |

**诚实的收益评估**：对 AAR（`--disable-frontend`、只链 `libmp3lame`）而言，4.0 的可利用性问题基本落在 frontend 侧，**安全收益有限**；真正价值是"不再停留在 2017 年的代码基线上"，把后续维护窗口打开。

**结论**：升，但明确它是"维护性升级"，别期待可感知的质量提升。

**构建差异（已实测）**：4.0 把 mpg123 从"可选依赖"改成**强制检查**，缺失直接报错退出：

```bash
# 3.100 的写法在 4.0 上失败
./configure ... --disable-frontend --disable-gtktest --with-pic
#   → configure: error: no, libmpg123 not found

# 4.0 必须显式关掉解码器
./configure ... --disable-frontend --disable-decoder --disable-gtktest --with-pic
#   → exit 0
```

其他：`--disable-efence` / `--disable-fast-install` / `--disable-maintainer-mode` 已不在 `--help` 里列出，但 autoconf 对未识别的 `--disable-*` 仅告警不中断，可保留；`--with-pic` 仍被识别。4.0 自带预生成的 `configure`，`autoreconf_library` 的短路条件（`! -f configure`）会跳过重生成，正是我们要的。

**同时要修 `build-ffmpeg-ndk-27d.sh` 里的三处 lame 硬编码**（当前状态）：

| 位置 | 现状 | 需改为 |
|---|---|---|
| 第 184–196 行 configure | 无 `--disable-decoder` | 加 `--disable-decoder`（否则 4.0 configure 直接失败） |
| 第 177–181 行解压 | `tar xzf /home/pisces312/lame-3.100.tar.gz` | 指向 `lame-4.0.tar.gz` |
| 短路条件 | 第 172 行 `[ ! -f .../mp3lame.pc ]` | **`mp3lame.pc` 从来没被生成过**（`prebuilt/.../pkgconfig/` 里只有 x264/x265/libav*），所以条件恒真 → lame 每次构建都重编。可改成判断 `libmp3lame.a` 单一条件，或手工补一个 `mp3lame.pc` |

> 第三点解释了为什么每次跑构建脚本都觉得"lame 又要编一遍"——不是错觉，是短路条件写错了。FFmpeg 的 configure 用 `require "libmp3lame >= 3.98.3" lame/lame.h ...` 直接探符号，不依赖 pkg-config，所以功能上一直没问题。

---

### D5 决策：AAC —— 暂不引入 fdk-aac 3.0.0

先厘清"aac 有最新源代码"指向哪个东西——这里有三个不同对象：

| 对象 | 现状 | 升级可能性 |
|---|---|---|
| **FFmpeg 内置 `aac` 编码器** | 随 FFmpeg 版本走。n8.1.3 里最后一次实质改动是 2025-06（移除 iirfilter / psy 预处理） | 升级 FFmpeg 才有变化。**n8.1→n9.0 的 aacenc 改动全是多声道 PCE/通道布局**（7.1、6.1、FLC/FRC），立体声无收益 → 不构成升 9.0 的理由 |
| **libfdk-aac 3.0.0** | 上游 2026-10-11 发布 | 可引，但是**净新增**，不是"更新" |
| **libopencore-amrnb** | 从未启用 | 与本议题无关（AMR-NB，非 AAC） |

**libfdk-aac 3.0.0 的具体情况**：

- 新增独立库 **`fdk-xhe-aac`**（xHE-AAC 编码），主库仍为 `fdk-aac`
- 上游明确"building with the Android NDK"修复，交叉编译友好
- 构建支持 CMake 与 autotools 双路径
- FFmpeg 侧：`--enable-libfdk-aac`，需 `--enable-nonfree`（当前 configure 已带）
- 代价：AAR +约 1.5–2.5 MB；**Fraunhofer 许可与 GPL 不兼容**，产物无法以纯 GPL 分发

**结论**：本次不引入。理由：
1. 8.1.3 的目标是"零行为变化的补丁升级"，引新编码器违背这个定位；
2. AAC 是 App 默认音频编码器（`AudioEncoder.kt:187`），换实现等于换音质基线，需要独立的听感与码率回归，成本远超重建本身；
3. 若确实要提升 AAC 质量（尤其 ≤96 kbps），应作为**独立项目**：加 `libfdk-aac` → 保留内置 `aac` 作为回退 → 在 `AudioEncoder` 里做成可选项，而不是直接替换。

> 反过来说，如果目标是"同一码率下明显更好的 AAC"，fdk-aac 是当前唯一实质性选择（FFmpeg 内置 aac 在低码率下明显弱于 fdk）。这条值得单独立项评估。

---

## 1. 基线（2026-10-31 实测）

### 1.1 两个仓库的真实角色

| 路径 | 角色 | 实际状态 |
|---|---|---|
| `D:\3rd-party-projects\ffmpeg-kit` | fork：JNI 移植层 + AAR 工程 + 构建脚本 | `main` @ `6635c31`；另有 `ffmpeg-8.1` 分支 @ `4b944e0`（含 MediaCodec 硬编）；工作树未提交：`README.md`/`CLAUDE.md`（文档索引调整）、`prebuilt/android-arm64-lts/ffmpeg/lib/libavutil.so`、`src/{cpu-features,ffmpeg,lame,x264,x265}`（370 MB 未跟踪） |
| `D:\3rd-party-projects\ffmpeg-8.1` | FFmpeg 8.1 源码快照 | 单提交 `e1689c6 init`；**无 remote、无 tag**；工作树混着上次构建产物（`config.h`、`*.o`、被删的 `ffmpeg`/`ffprobe` 二进制） |
| `/home/pisces312/ffmpeg-8.1` | WSL 侧软链 | → `/mnt/d/3rd-party-projects/ffmpeg-8.1`（构建脚本读写的就是 D 盘这份） |

**结论（决定方案形态）**：`ffmpeg-8.1` 不是上游 git 仓库，没有历史可 `fetch/checkout`，且工作树被构建产物污染（`make distclean` 清不净已提交的 `.o`）。因此**不原地升级**，而是新落一份干净的 8.1.3 源码，旧目录原样保留做回退。

### 1.2 构建流水线（现状）

| 步骤 | 脚本 | 关键输入 | 关键输出 |
|---|---|---|---|
| 1. 依赖 + FFmpeg | `build-ffmpeg-ndk-27d.sh` | `NDK=~/android-ndk-r27d`（27.3.13750724）、`TARGET=aarch64-linux-android24` | `prebuilt/android-arm64/ffmpeg/{lib,include}` |
| 2. JNI | `build-jni-ndk-r27d.sh` | `android/jni/Android.mk`（45 个 `fftools_*` 源文件） | `libffmpegkit.so`、`libffmpegkit_abidetect.so` |
| 3. 打包 | `build-aar-ndk-r27d.sh` | `cmd.exe /c gradlew.bat assembleRelease` | `ffmpeg-kit-release.aar` → `llvm-strip` 重打包 |

**已知失效点（必须先修，否则全流程直接失败）**：

| 位置 | 现值 | 应为 |
|---|---|---|
| 三个脚本的 `BASEDIR` | `/mnt/d/nili/3rd_party_projects/ffmpeg-kit` | `/mnt/d/3rd-party-projects/ffmpeg-kit` |
| `build-ffmpeg-ndk-27d.sh` 的 `FFMPEG_SRC` | `/home/pisces312/ffmpeg-8.1` | `/mnt/d/3rd-party-projects/ffmpeg-8.1.3` |
| `prebuilt/.../lib/pkgconfig/*.pc` 的 `prefix=` | `.../nili/3rd_party_projects/...` | 同上新路径（**不改会把 -I/-L 指到不存在的目录**） |
| `build_scripts/*.py` | `/home/pisces312/ffmpeg-kit-8.1/...` | 仓库新路径 |

### 1.3 当前产物

- `prebuilt/android-arm64/ffmpeg/lib/`：7 个 `.so`，构建于 2026-05-13；`include/` 997 个 `.h`
- AAR：12,625,191 B，内含 10 个 `.so`（`libavcodec.so` 16,034,896 B 未压缩）
- StreamClip 引用点：`app/build.gradle.kts` `implementation(files("libs/ffmpeg-kit-8.1.aar"))`
- 版本号两处：`android/ffmpeg-kit-android-lib/build.gradle`（`versionName "8.1"`、`versionCode 240810`）、`ffmpegkit.h` 的 `FFMPEG_KIT_VERSION "8.1"`

**⚠️ 本轮新发现的两个问题（本次重建顺带修掉）**

| 问题 | 证据 | 本次处理 |
|---|---|---|
| `prebuilt/.../include/config.h` 与 `.so` **不是同一次 configure** | `config.h`（05-13 22:02）内嵌的是**精简版二进制**参数 `--disable-everything --enable-encoder='libx264,libx265,aac,...'`，而 `.so`（22:48）是 AAR 参数（含 mediacodec）编的 | Step 2 回填后强制断言 `FFMPEG_CONFIGURATION` 含 `mediacodec`（见 §4 Step 2 校验） |
| `libopus` 编码器不存在但被调用 | `AudioEncoder.kt:199` 用 `-c:a libopus`，当前 `.so` 内 `libopus` 命中 0（只有实验性原生 `opus`） | 见下方"待决策 D1" |

---

## 2. 8.1 → 8.1.3 改了什么

### 2.1 总量与兼容性

| 指标 | n8.1 | n8.1.3 | 判定 |
|---|---|---|---|
| 上游提交 | — | **508 个提交 / 300 个文件** | 补丁级发布，改动集中在解封装与安全加固 |
| `libavutil` 版本 | 60.26.**100** | 60.26.**103** | 仅 micro，SONAME `libavutil.so.60` 不变 |
| `FF_API_*` 废弃宏数量（avutil/avcodec/avformat/avfilter） | 0/9/5/4 | **0/9/5/4** | **零 API 删除**，移植层无编译级破坏 |
| 官方发布包 | — | `ffmpeg-8.1.3.tar.xz` 11,732,548 B，Last-Modified 2026-09-21 | 正式发布（非分支快照） |

### 2.2 fftools 变更清单（全部 7 个文件，+95/−41）

| 文件 | 增/删 | 内容 | 与本地改造是否重叠 |
|---|---|---|---|
| `ffmpeg_demux.c` | +53/−35 | `readrate_sleep()` 重构（按"最慢流"计、`resume_pts`→`resume_progress`）；`ifile_open()` 新增 `-t` 负值拒绝 | 否（本地只改了 3 行 include） |
| `ffmpeg_mux_init.c` | +25/−1 | `ost_add()` 新增视频流 `disposition` 继承与掩码；`set_dispositions()` 配套 | 否（本地只改 5 行 include） |
| `ffmpeg_dec.c` | +11/−2 | `subtitle_header` 改为 `av_mallocz` 拷贝（ASS 要求 NUL 结尾）+ `dec_free` 释放 | 否（本地只改 1 行 include） |
| `ffmpeg_opt.c` | +2/−0 | `opt_map()` 增加 `stream_index` 边界校验（越界修复） | 否（本地只改 4 行 include） |
| `ffmpeg.h` | +1/−1 | `const uint8_t *subtitle_header` → `uint8_t *` | 否（本地是 include + 3 个声明） |
| `opt_common.c` | +2/−2 | `print_program_info()` 把宏拼接改为 `%s` 参数 | 否（**本地该函数未被改动**，已核对） |
| `graph/graphprint.c` | +1/−0 | 补 `#include "libavutil/mem.h"` | 否（本地改的是 include 前缀） |

### 2.3 三处行为变更 × 本项目（逐项核验，均为空集）

| 8.1.3 行为变更 | 影响面 | 本项目实际情况 |
|---|---|---|
| `-re` / readrate 重构 | 仅 `-re` 实时限速路径 | 全代码库 **0 处** `-re` / `readrate` |
| `-t` 必须非负（否则 `AVERROR(EINVAL)` 中止） | 传负值时 | 唯一一处 `append("-t $durationSec ")`（`FFmpegService.kt:316`），取值为时长，恒为正 |
| 视频流 `disposition` 继承并掩码到 `ATTACHED_PIC` | 多轨 mp4 的 default/forced 标记 | **0 处** `disposition` 相关代码 |

即：8.1.3 的三项行为变更对本项目是**空集**，回归风险主要集中在库层而非 CLI 层。

### 2.4 值得升级的修复

1. **`ffmpeg_dec.c` 字幕头越界**：上游此前把 `dec_ctx->subtitle_header` 直接指针共享给 `Decoder`，ASS 解码假设缓冲区 NUL 结尾，存在越界读。8.1.3 改为独立 `av_mallocz(size+1)` 拷贝。这是内存安全问题，与"连续多次执行"场景相关。
2. **`ffmpeg_opt.c` `opt_map()` 越界**：`input_files[m->file_index]->streams[m->stream_index]` 未校验 `stream_index`，可被异常 `-map` 触发。
3. **库层 mov 解封装加固**：trun 样本数、sgpd entry_count、iref 计数、dts 溢出等 7 处边界/溢出修复（与 9.0 同批回移）。这是本项目唯一直接受益面——裁剪/合并走的正是 mov 解析。

### 2.5 明确**不需要**改的部分

| 项 | 判定依据 |
|---|---|
| `android/jni/Android.mk` 的 `MY_SRC_FILES` | 8.1.3 的 fftools **无新增/删除文件**，45 个源文件清单不变 |
| `fftools_graph_css.c`、`fftools_graph_html.c` | 上游 `fftools/resources/` 未变更，无需重新生成 |
| `configure` 选项 | 补丁级发布，选项集合无变化（沿用现有 12 项 enable/disable） |
| Java 层 | 无 API 变化，`classes.jar` 应字节级等价（第 6 节校验） |

---

## 3. 移植面测绘

### 3.1 文件映射规则（45 个文件）

上游 `fftools/` 被 flatten 到 `android/ffmpeg-kit-android-lib/src/main/cpp/`，统一加 `fftools_` 前缀（改造分类与 45 个文件的成因见 [`ffmpeg-build.md`](./ffmpeg-build.md) §3.6）：

| 上游 | 本地 | 数量 |
|---|---|---|
| `fftools/*.c`、`fftools/*.h` | `fftools_<原名>` | 24 |
| `fftools/graph/graphprint.{c,h}` | `fftools_graphprint.{c,h}` | 2 |
| `fftools/resources/resman.{c,h}` | `fftools_resman.{c,h}` | 2 |
| `fftools/resources/graph.css` / `graph.html`（bin2c 生成物） | `fftools_graph_css.c` / `fftools_graph_html.c` | 2（保留，不重生成） |
| `fftools/textformat/avtextformat.c/.h` | `fftools_textformat.c/.h` | 2 |
| `fftools/textformat/avtextwriters.h` | `fftools_avtextwriters.h` | 1 |
| `fftools/textformat/tf_*.c`、`tf_*.h` | `fftools_tf_*.c/.h` | 9 |
| `fftools/textformat/tw_*.c` | `fftools_tw_*.c` | 3 |

配套 include 改名（15 个 basename）：`cmdutils.h`、`ffmpeg.h`、`ffmpeg_sched.h`、`ffmpeg_utils.h`、`ffmpeg_mux.h`、`opt_common.h`、`fopen_utf8.h`、`sync_queue.h`、`thread_queue.h`、`avtextformat.h`、`avtextwriters.h`、`tf_internal.h`、`tf_mermaid.h`、`graphprint.h`、`resman.h`。

### 3.2 本地改造规模（diff 忽略 CRLF，单位：行）

| 文件 | 改动行 | 性质 |
|---|---|---|
| `fftools_opt_common.c` | 229 | 103 处 `printf(` → `av_log(NULL, AV_LOG_STDERR, `；移除 `av_log_set_callback(log_callback_help)` |
| `fftools_tw_stdout.c` | 108 | 整体重写：stdout writer → 按行 flush 的 avlog writer |
| `fftools_ffmpeg.c` | 57 | `report_callback`/`forward_report` 钩子、`ffmpeg_cleanup` 计数器复位、`program_name` 去 const |
| `fftools_ffprobe.c` | 20 | `main`→`ffprobe_execute`、`show_help_default_ffprobe` 改名、去掉 help callback 覆盖 |
| `fftools_cmdutils.c` | 16 | help 输出 → stderr |
| `fftools_graphprint.c` | 12 | include 前缀 + 路径 |
| `fftools_ffmpeg_mux.c` | 11 | SDP → `av_log(AV_LOG_STDERR)` + include |
| `fftools_ffmpeg_mux_init.c` / `fftools_ffmpeg_sched.c` / `fftools_ffmpeg.h` | 10 | 纯 include 前缀（`.h` 另加 3 个函数声明） |
| `fftools_cmdutils.h` | 9 | `program_name` 去 const、`AV_LOG_STDERR -16`、`show_help_default_ffprobe` 声明 |
| `fftools_ffmpeg_opt.c` | 8 | 纯 include 前缀 |
| `fftools_ffmpeg_demux.c` | 6 | 纯 include 前缀 |
| `fftools_*`（dec/enc/filter/hw/sync_queue/thread_queue/mux.h/sched.h/opt_common.h/textformat/resman/tf_json 等） | ≤4 | 纯 include 前缀或零改动 |

**归纳为三类**：
- **A 类 机械**：include 前缀改名（全量可脚本化）
- **B 类 输出通道**：`printf/stdout` → `av_log(AV_LOG_STDERR)/stderr`（`opt_common.c`、`cmdutils.c`、`ffmpeg_mux.c`、`tw_stdout.c`）
- **C 类 手工钩子**：`program_name` 去 const、`report_callback` 转发、`ffmpeg_execute`/`ffprobe_execute` 入口、`show_help_default_ffprobe` 改名、`AV_LOG_STDERR` 定义、`ffmpeg_cleanup` 计数器复位

### 3.3 冲突预判（8.1.3 只动了 7 个文件，逐个断言）

| 本地文件 | 本地改动 | 8.1.3 改动位置 | 预期 |
|---|---|---|---|
| `fftools_ffmpeg_demux.c` | 3 行 include（文件头 ~20 行） | `readrate_sleep()`（~515）、`ifile_open()`（~1929） | 自动合并 |
| `fftools_ffmpeg_mux_init.c` | 5 行 include（文件头） | `ost_add()`（~1203/1260）、`set_dispositions()`（~3118） | 自动合并 |
| `fftools_ffmpeg_dec.c` | 1 行 include | `dec_free()`（~136）、`dec_open()`（~1621） | 自动合并 |
| `fftools_ffmpeg_opt.c` | 4 行 include | `opt_map()`（~645） | 自动合并 |
| `fftools_ffmpeg.h` | include + 3 声明（文件尾） | `Decoder` 结构（~469） | 自动合并 |
| `fftools_opt_common.c` | 229 行（`show_*` 系列） | `print_program_info()`（~196，本地未改此函数） | 自动合并 |
| `fftools_graphprint.c` | include 段（~29-42） | 新增 `libavutil/mem.h`（~36 之间） | 自动合并 |

**7 个文件预期 0 冲突**。剩余 38 个 `fftools_*` 文件在 8.1 → 8.1.3 之间完全未变，**不需要触碰**——这是本次移植量远小于 9.0（26 文件）的根本原因。

---

## 4. 执行方案

> 全部命令在 **WSL2 Ubuntu** 内执行（Git Bash 无法跑 configure/make，且本机 Git Bash 的 curl 连接 ffmpeg.org 无响应，WSL 内正常）。

### Step 0　前置整理（约 10 分钟）

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit

# 0.1 隔离分支（不污染 main）
git switch -c ffmpeg-8.1.3

# 0.2 修正脚本内失效路径
sed -i 's#^export BASEDIR=.*#export BASEDIR=/mnt/d/3rd-party-projects/ffmpeg-kit#' \
    build-ffmpeg-ndk-27d.sh build-jni-ndk-r27d.sh build-aar-ndk-r27d.sh
sed -i 's#^export FFMPEG_SRC=.*#export FFMPEG_SRC=/mnt/d/3rd-party-projects/ffmpeg-8.1.3#' \
    build-ffmpeg-ndk-27d.sh

# 0.3 修正 pkg-config 的旧 prefix（否则 ffmpeg configure 找不到 x264/x265/lame）
sed -i 's#/mnt/d/nili/3rd_party_projects#/mnt/d/3rd-party-projects#g' \
    prebuilt/android-arm64/ffmpeg/lib/pkgconfig/*.pc
grep -h '^prefix=' prebuilt/android-arm64/ffmpeg/lib/pkgconfig/*.pc

# 0.4 备份现有 prebuilt（保留 8.1 可回退，约 200MB）
cp -a prebuilt/android-arm64 prebuilt/android-arm64-8.1-backup

# 0.5 顺手把大目录排除出版本控制（当前 src/ 370MB 处于未跟踪状态）
printf '\nsrc/*/\nprebuilt/\nbuild-8.1.*.log\n' >> .gitignore
```

**校验**：`grep -n "BASEDIR\|FFMPEG_SRC" build-*.sh` 全部指向新路径。

### Step 1　获取 8.1.3 源码（约 10 分钟）

```bash
cd /tmp
curl -L --retry 3 --connect-timeout 15 -o ffmpeg-8.1.3.tar.xz \
  https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz
ls -l ffmpeg-8.1.3.tar.xz                     # 期望 11,732,548 字节

tar xJf ffmpeg-8.1.3.tar.xz -C /mnt/d/3rd-party-projects/
cd /mnt/d/3rd-party-projects/ffmpeg-8.1.3

cat VERSION RELEASE                            # 期望 8.1.3 / 8.1.3
grep -E "LIBAVUTIL_VERSION_(MAJOR|MINOR|MICRO)" libavutil/version.h
                                               # 期望 60 / 26 / 103
```

**为什么用 tarball，而不是在 `ffmpeg-8.1` 里 `git fetch`**：

| 通道 | 可行性 | 说明 |
|---|---|---|
| `ffmpeg.org` tarball | ✅ 首选 | WSL 内 HTTP 200，11.2 MB，正式发布包 |
| `git fetch` 上游 tag | ⚠️ 不可行 | `ffmpeg-8.1` 无 remote；且 github.com:443 在本机被阻断 |
| `gh api .../tarball/n8.1.3` | ✅ 备选 | api.github.com 可通，产物为 `FFmpeg-n8.1.3.tar.gz`（无 `VERSION`/`RELEASE` 差异，但含 git 元信息） |

保留 `ffmpeg-8.1` 目录不动，作为 8.1 的**可回退构建源**。

### Step 1.5　升级外部依赖库（约 25–40 分钟）

对应 D2–D5 的结论：x264 **不动**，x265 追平上游，lame 换 4.0，fdk-aac 不引入。

#### 1.5.1 备份当前外部库产物

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit
mkdir -p /tmp/extlib-backup
cp -a prebuilt/android-arm64/ffmpeg/lib/libx264.a \
      prebuilt/android-arm64/ffmpeg/lib/libx265.a \
      prebuilt/android-arm64/ffmpeg/lib/libmp3lame.a \
      prebuilt/android-arm64/ffmpeg/lib/pkgconfig/x264.pc \
      prebuilt/android-arm64/ffmpeg/lib/pkgconfig/x265.pc \
      /tmp/extlib-backup/
ls -l /tmp/extlib-backup/    # 基线：1,815,426 / 2,655,314 / 432,658 B
```

#### 1.5.2 x265：拉最新 master

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit/src/x265
git remote -v                     # 应指向 bitbucket.org/multicoreware/x265_git
git fetch origin master
git log -1 --format="%h %ci" origin/master      # 期望 b81f650 2026-06-23
git checkout master && git reset --hard origin/master
grep -m1 "set(X265_BUILD" source/CMakeLists.txt # 期望 216（若变，记下新值）
```

> 若 `git fetch` 走不通（GitHub 被阻断，bitbucket 一般可通），退用 `gh api` 或 `curl -L https://bitbucket.org/multicoreware/x265_git/get/b81f650.tar.gz` 覆盖 `src/x265`，但会丢 git 元数据。

#### 1.5.3 lame：3.100 → 4.0

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit/src
rm -rf lame lame-4.0
curl -L --retry 3 -o lame-4.0.tar.gz \
  "https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz"
ls -l lame-4.0.tar.gz              # 期望 1,496,810 B
tar xzf lame-4.0.tar.gz && mv lame-4.0 lame
grep -m1 "PACKAGE_VERSION=" lame/configure   # 期望 '4.0'
ls lame/configure                  # 必须存在（预生成，避免触发 autoreconf）
```

#### 1.5.4 改 `build-ffmpeg-ndk-27d.sh`（三处）

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit

# (a) lame configure 增加 --disable-decoder（4.0 强制要求 mpg123，缺失会直接失败）
sed -i 's|--disable-frontend \\|--disable-frontend \\\n        --disable-decoder \\|' build-ffmpeg-ndk-27d.sh

# (b) 解压源改为 4.0
sed -i 's|lame-3\.100\.tar\.gz|lame-4.0.tar.gz|g; s|mv lame-3\.100 lame|mv lame-4.0 lame|g' build-ffmpeg-ndk-27d.sh

# (c) 修短路条件：mp3lame.pc 从未生成过，导致 lame 每次都重编
sed -i 's#if \[ ! -f "\$PREFIX/lib/libmp3lame.a" \] || \[ ! -f "\$PREFIX/lib/pkgconfig/mp3lame.pc" \]; then#if [ ! -f "$PREFIX/lib/libmp3lame.a" ]; then#' build-ffmpeg-ndk-27d.sh

grep -n "disable-decoder\|lame-4.0\|libmp3lame.a" build-ffmpeg-ndk-27d.sh | head -6
```

> (a) 的 sed 用 `\\` 匹配行尾续行符；改完务必肉眼确认 configure 段结构没坏——`sed` 插入多行续行容易出错，手工编辑更稳。

#### 1.5.5 删旧产物，触发重编

```bash
# 只删 x265 和 lame，x264 保留（D2：不升）
rm -f prebuilt/android-arm64/ffmpeg/lib/libx265.a \
      prebuilt/android-arm64/ffmpeg/lib/libmp3lame.a \
      prebuilt/android-arm64/ffmpeg/lib/pkgconfig/x265.pc
ls prebuilt/android-arm64/ffmpeg/lib/*.a      # 应只剩 libx264.a
```

#### 1.5.6 校验（构建后）

```bash
P=prebuilt/android-arm64/ffmpeg

# x265 版本：应仍为 216（若上游改过 BUILD，pkg-config 也要同步）
grep -m1 "^Version:" $P/lib/pkgconfig/x265.pc          # 4.2
strings $P/lib/libx265.a | grep -m1 "4\.2" || true     # 可能有版本串

# lame 4.0：库体内有 libmp3lame 版本串
strings $P/lib/libmp3lame.a | grep -m1 "3\.100\|4\.0"  # 期望不再出现 3.100

# 体积对照（±10% 以内合理）
ls -l $P/lib/libx265.a $P/lib/libmp3lame.a
```

> lame 4.0 的版本串在 `libmp3lame/version.h` 编译进 `lame_version[]`，`strings` 应能看到 `4.0`；若只看到 3.100 说明源码没换成功。

### Step 2　重建 libav*（约 30–50 分钟构建）

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit
export FFMPEG_SRC=/mnt/d/3rd-party-projects/ffmpeg-8.1.3   # Step 0.2 已改脚本内默认值
FORCE_FFMPEG=1 ./build-ffmpeg-ndk-27d.sh 2>&1 | tee build-8.1.3.log
```

- `FORCE_FFMPEG=1` 强制重编 FFmpeg（否则脚本见 `libavcodec.so` 存在会跳过）
- **x265 / lame 会连带重编**：Step 1.5.5 删了它们的 `.a`，脚本的短路条件会自动补上；x264 因 `.a` 还在而跳过
- 日志检查点：`>>> Building x265...` 与 `>>> Building lame...` 都应出现；`>>> x264 already built, skipping` 是预期
- 首次在全新源码树上跑，`make distclean` 会报错但被 `|| true` 吞掉，属正常
- 顺序很重要：外部库必须先于 FFmpeg 编完，否则 configure 的 `require` 测试找不到 `-lx265` / `-lmp3lame`

**紧接着必须补做内部头文件回填**（历史坑：`make install` 只装公开头文件，JNI 层编不过）：

```bash
PREFIX=prebuilt/android-arm64/ffmpeg
SRC=/mnt/d/3rd-party-projects/ffmpeg-8.1.3
mkdir -p $PREFIX/include/libavutil/{x86,arm,aarch64} $PREFIX/include/libavcodec/{x86,arm}
for h in config.h \
         libavcodec/mathops.h libavcodec/x86/mathops.h libavcodec/arm/mathops.h \
         libavformat/network.h libavformat/os_support.h libavformat/url.h \
         libavutil/attributes_internal.h libavutil/bprint.h libavutil/getenv_utf8.h \
         libavutil/internal.h libavutil/libm.h libavutil/reverse.h \
         libavutil/thread.h libavutil/timer.h \
         libavutil/x86/asm.h libavutil/x86/timer.h libavutil/arm/timer.h \
         libavutil/aarch64/timer.h libavutil/x86/emms.h; do
  cp -f "$SRC/$h" "$PREFIX/include/$h" || echo "MISS $h"
done
```

**Step 2 校验**：

```bash
grep FFMPEG_VERSION $PREFIX/include/libavutil/ffversion.h   # 期望 "8.1.3"
grep -m1 LIBAVUTIL_VERSION_MINOR $PREFIX/include/libavutil/version.h   # 26
strings $PREFIX/lib/libavutil.so | grep -E '^8\.1\.[0-9]$'  # 期望 8.1.3
readelf -d $PREFIX/lib/libavutil.so | grep SONAME          # libavutil.so.60（不变）
ls -la $PREFIX/lib/*.so                                     # 7 个

# ★ 必查：config.h 必须与本次 .so 同源（修复 §1.3 的历史隐患）
grep -o 'FFMPEG_CONFIGURATION ".*' $PREFIX/include/config.h | grep -c mediacodec            # 期望 1
grep -o 'FFMPEG_CONFIGURATION ".*' $PREFIX/include/config.h | grep -c disable-everything    # 期望 0
diff <(grep -o 'FFMPEG_CONFIGURATION ".*' $PREFIX/include/config.h) \
     <(grep -o 'FFMPEG_CONFIGURATION ".*' $SRC/config.h) && echo "config.h 与构建树一致"
```

### Step 3　移植 7 个 fftools 文件（约 30 分钟）

采用**三方合并**：把 n8.1 与 n8.1.3 都先做同样的 include 改名（使其与本地命名一致），再以本地文件为 `ours` 做 `git merge-file`。这样本地的手工改动自动叠加到 8.1.3 上，只有真正重叠处才冲突。

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit
BASE=src/ffmpeg/fftools
NEW=/mnt/d/3rd-party-projects/ffmpeg-8.1.3/fftools
CPP=android/ffmpeg-kit-android-lib/src/main/cpp
W=/tmp/fftools-813; rm -rf $W; mkdir -p $W

MAP="ffmpeg.h:fftools_ffmpeg.h
ffmpeg_dec.c:fftools_ffmpeg_dec.c
ffmpeg_demux.c:fftools_ffmpeg_demux.c
ffmpeg_mux_init.c:fftools_ffmpeg_mux_init.c
ffmpeg_opt.c:fftools_ffmpeg_opt.c
graph/graphprint.c:fftools_graphprint.c
opt_common.c:fftools_opt_common.c"

# 注意分隔符用 %，不能与正则里的 | 相撞
RENAME='s,%include "(cmdutils|ffmpeg|ffmpeg_sched|ffmpeg_utils|ffmpeg_mux|opt_common|fopen_utf8|sync_queue|thread_queue|avtextformat|avtextwriters|tf_internal|tf_mermaid|graphprint|resman)\.h",%include "fftools_\1.h",g'

for e in $MAP; do
  up=${e%%:*}; loc=${e##*:}
  sed -E "$RENAME" "$BASE/$up" > "$W/base_$loc"
  sed -E "$RENAME" "$NEW/$up"  > "$W/new_$loc"
  sed 's/\r$//' "$CPP/$loc"    > "$W/local_$loc"      # 统一 LF，避免行尾噪声
  if git merge-file -p --diff3 "$W/local_$loc" "$W/base_$loc" "$W/new_$loc" > "$W/merged_$loc"; then
      echo "OK       $loc"
  else
      echo "CONFLICT $loc  (冲突数见 $W/merged_$loc)"
  fi
done
```

**逐个确认无冲突后落位**：

```bash
for e in $MAP; do loc=${e##*:}; cp "$W/merged_$loc" "$CPP/$loc"; done
```

**落位后断言（必须全部成立）**：

```bash
grep -c 'report_callback'        $CPP/fftools_ffmpeg.c        # >0，钩子还在
grep -c 'nb_output_files = 0'    $CPP/fftools_ffmpeg.c        # 1，double-execute 修复还在
grep -c 'int ffmpeg_execute'     $CPP/fftools_ffmpeg.h        # 1
grep -c 'int ffprobe_execute'    $CPP/fftools_ffprobe.c       # 1
grep -c 'AV_LOG_STDERR    -16'   $CPP/fftools_cmdutils.h      # 1
grep -c 'printf('                $CPP/fftools_opt_common.c    # 0（103 处已全转 av_log）
grep -c 'av_log(NULL, AV_LOG_STDERR' $CPP/fftools_opt_common.c # 108
grep -c 'avtextwriter_create_stdout' $CPP/fftools_tw_stdout.c  # ≥1
grep -c 'av_freep(&dp->dec.subtitle_header)' $CPP/fftools_ffmpeg_dec.c  # 1（8.1.3 新修复已进来）
grep -c 'subtitle_header'        $CPP/fftools_ffmpeg.h        # 类型应为 uint8_t *
```

### Step 4　JNI + AAR（约 20 分钟）

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit
./build-jni-ndk-r27d.sh 2>&1 | tee jni-8.1.3.log
./build-aar-ndk-r27d.sh  2>&1 | tee aar-8.1.3.log
```

- 该链路走 `ndk-build`（`-Wall -Werror`）+ `cmd.exe /c gradlew.bat`
- 若因 8.1.3 新代码触发新告警而 `-Werror` 失败：**只加 `-Wno-xxx` 到 `Android.mk` 的 `MY_CFLAGS`**，不改上游源码

### Step 5　版本号与接入（约 10 分钟）

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit
sed -i 's/versionName "8.1"/versionName "8.1.3"/' android/ffmpeg-kit-android-lib/build.gradle
sed -i 's/#define FFMPEG_KIT_VERSION "8.1"/#define FFMPEG_KIT_VERSION "8.1.3"/' \
    android/ffmpeg-kit-android-lib/src/main/cpp/ffmpegkit.h

cp android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar \
   /d/my-projects/StreamClip/app/libs/ffmpeg-kit-8.1.3.aar
```

StreamClip 侧改一行（`app/build.gradle.kts`）：

```kotlin
implementation(files("libs/ffmpeg-kit-8.1.3.aar"))   // 原：ffmpeg-kit-8.1.aar
```

旧 AAR `app/libs/ffmpeg-kit-8.1.aar` **保留不删**，作为回退资产。

### Step 6　校验（约 20 分钟）

| 检查项 | 命令 | 期望 |
|---|---|---|
| AAR 版本 | `./check-aar-ffmpeg-version.sh /d/my-projects/StreamClip/app/libs/ffmpeg-kit-8.1.3.aar` | 该脚本按 `strings` 猜 SONAME，可能匹配不到；以 `readelf -d` 的 `SONAME libavutil.so.60` 为准 |
| so 数量 | `unzip -l <aar> \| grep -c '\.so$'` | 10 |
| JNI 入口 | `unzip -p <aar> jni/arm64-v8a/libffmpegkit.so > /tmp/x.so && nm -D --defined-only /tmp/x.so \| grep -c ffmpeg_execute` | ≥1 |
| Java API 未变 | `unzip -l <aar> \| grep classes.jar`，解包后比 `com/arthenica/ffmpegkit/` 类清单 | 与 8.1 完全相同 |
| 体积 | `ls -l <aar>` | 11.9–13.3 MB（12.6 MB ±5%） |
| 未见调试符号 | `readelf -S jni/arm64-v8a/libavcodec.so \| grep -c debug_info` | 0（strip 生效） |

---

## 5. 真机回归清单（10 项）

| # | 用例 | 断言 |
|---|---|---|
| 1 | 无损裁剪（`-ss/-t -c copy`） | 输出时长误差 <0.1s；`ffprobe` 起止 pts 正确 |
| 2 | 多段合并（concat demuxer） | 总时长 = 各段之和 ±0.1s；无音画不同步 |
| 3 | 提取音频（`-vn -c:a copy` / aac） | 采样率/声道数不变；可播放 |
| 4 | MediaCodec 硬编压缩（h264/hevc） | 成功返回；输出可播；耗时不劣化 >15% |
| 5 | libx264 / libx265 软编（GPL 路径） | 成功返回；同 CRF 下体积与 8.1 差异 <3%。**x265 已换新版，需单独记录一次基准** |
| 6 | 旋转元数据 | 竖屏素材裁剪后方向仍正确（`Mp4RotationUtils.copyRotation` 仍生效） |
| 7 | ffprobe 元信息 | `GetMediaInformation` 返回非空 JSON（验证 `tw_stdout.c` 的 avlog 重定向仍在） |
| 8 | help/错误输出 + 连续执行 | 错误信息进 Java 日志（验证 `opt_common.c` 的 `AV_LOG_STDERR` 仍在）；同进程连续执行 10 次不崩（验证 `ffmpeg_cleanup` 计数器复位仍在） |
| 9 | **MP3 导出（lame 4.0）** | `-c:a libmp3lame` 成功；CBR/VBR 两种模式各导一次；对比 8.1 产物的时长/码率一致，听感无明显差异 |
| 10 | **FLAC / WAV 导出** | `-c:a flac`、`-c:a pcm_s16le` 仍可用（验证默认组件集未被 configure 变更挤掉） |

> 第 7、8 项最易漏——它们验证的正是**本地改造是否在合并中存活**，而不是 8.1.3 本身。
> 第 9 项是本次新增的外部库升级唯一需要听感确认的路径；第 10 项防的是"改 configure 时误伤默认组件"。

---

## 6. 风险与回退

| 风险 | 概率 | 影响 | 对策 |
|---|---|---|---|
| 7 个文件合并冲突 | 低（已逐处预判 0） | 中 | `git merge-file --diff3` 逐文件，冲突处人工复核（均为上下文偏移，非语义冲突） |
| 内部头文件漏回填 → JNI 编译失败 | 中（历史踩过） | 高（阻塞） | Step 2 脚本化回填 + `ffversion.h` 校验；失败时从 `prebuilt/android-arm64-8.1-backup/include` 对照补 |
| `.pc` 旧 `prefix` → 链接到 `/mnt/d/nili/...` | 高（脚本未修） | 高 | Step 0.3 强制修正并 grep 验证 |
| **lame 4.0 configure 直接失败** | **确定（已实测）** | 高（阻塞） | Step 1.5.4 必须加 `--disable-decoder`，否则 `no, libmpg123 not found` |
| **x265 换版后 CRF 表现偏移** | 中 | 中 | 回归第 5 项单独记基准；若体积差异 >3% 可回退 `libx265.a`（`/tmp/extlib-backup/`） |
| NDK r27d + `-Werror` 新告警 | 中 | 中 | 仅加 `-Wno-*` 到 `MY_CFLAGS`，不动上游代码 |
| 8.1.3 库层改动引入新行为 | 低（三项变更均未触及） | 中 | 第 5 节回归清单 |
| AAR 体积增长超 8% | 低 | 低 | 记录基线；超限单独排查（体积优化另行立项，不与版本升级耦合） |
| 构建目录在 /mnt/d（9p 文件系统）偏慢 | 确定 | 低 | 可 `cp -a` 到 `~/ffmpeg-8.1.3` 并改 `FFMPEG_SRC` 一行提速 |

**回退路径（四选一，前三条 ≤5 分钟）**：

```bash
# A. 回到代码基线
git switch main                      # 或 git switch ffmpeg-8.1

# B. 回到 8.1 的预编译库（含旧外部库）
rm -rf prebuilt/android-arm64 && mv prebuilt/android-arm64-8.1-backup prebuilt/android-arm64
FORCE_FFMPEG= ./build-jni-ndk-r27d.sh && ./build-aar-ndk-r27d.sh

# C. 只回退外部库（FFmpeg 保持 8.1.3）
cp -a /tmp/extlib-backup/* prebuilt/android-arm64/ffmpeg/lib/   # x264/x265/lame 的 .a 与 .pc
cp -a /tmp/extlib-backup/x264.pc /tmp/extlib-backup/x265.pc prebuilt/android-arm64/ffmpeg/lib/pkgconfig/
rm -f prebuilt/android-arm64/ffmpeg/lib/*.so && FORCE_FFMPEG=1 ./build-ffmpeg-ndk-27d.sh

# D. 应用侧回退（最快）
# app/build.gradle.kts 改回 files("libs/ffmpeg-kit-8.1.aar")
```

---

## 7. 工时估算

| 阶段 | 人工 | 机器 |
|---|---|---|
| Step 0 前置整理 | 10 min | — |
| Step 1 取源码 | 5 min | 2 min 下载 + 解压 |
| **Step 1.5 外部库升级** | **20 min** | **10–15 min**（x265 + lame 两个库） |
| Step 2 重建 libav* + 头文件回填 | 15 min | 30–50 min |
| Step 3 移植 7 文件 | 30 min | — |
| Step 4 JNI + AAR | 10 min | 10–15 min |
| Step 5 版本号 + 接入 | 10 min | — |
| Step 6 校验 | 20 min | — |
| Step 7 真机回归 | 70–100 min | — |
| **合计** | **约 3 小时** | **约 1.2 小时** |

对比 9.0 方案（26 文件 +735/−511，全量回归 2–4 人日），本次仍是**半天量级**；外部库升级只增加约 30 分钟。

---

## 8. 后续建议（不与本次升级耦合）

1. **把本地改造固化为 patch/脚本**：当前是"改了但没留 patch"，每次升级都要人工比对。Step 3 的三方合并脚本可直接沉淀为 `build_scripts/port_fftools.py`（含 45 项映射 + 15 个 include 改名 + 断言集），下次升级从"半天"变"半小时"。
2. **把内部头文件回填并入 `build-ffmpeg-ndk-27d.sh`**：这是第二次踩同一个坑（详见 `ffmpeg-build.md` §3.5，含 20 个文件清单与 config.h 同源校验）。
3. **AAR 体积优化单独立项**：`libavcodec.so` 15.3 MB / 合计 25.8 MB（未压缩），与版本升级无关，应按实际用到的 codec/format 裁剪 configure。
4. **`fdk-aac` 独立评估（新增，源自 D5）**：若产品要提升 AAC 质量（尤其 ≤96 kbps），引 `libfdk-aac 3.0.0` 并保留内置 `aac` 作回退，在 `AudioEncoder` 里做成可选编码器。需单独评估许可影响（Fraunhofer 与 GPL 冲突）与 +2 MB 体积。
5. **外部库版本清单化（新增，源自 D2–D4）**：新增 `scripts/android/versions.conf`，固定记录"仓库 URL + tag/commit + X264_BUILD/X265_BUILD/lame 版本"，构建时断言。当前 `src/{x264,x265,lame}` 纯手工放置，已出现"实际 x265 4.2 / 上游脚本写 3.4"的漂移，且 lame 的 tarball 路径硬编码在脚本第 180 行。
6. **9.x 触发条件**（沿用评估结论）：8.1 分支 EOL、上游出现未回移的 movenc/mediacodec 修复、需要 9.x 独有能力、或安全公告涉及可触达解封装路径。

---

## 9. 执行记录（2026-10-31 实际完成）

**已完成，产物可用。** 全程约 26 分钟（19:32 → 19:58），其中构建机时约 12 分钟。

### 9.1 结果

| 项 | 值 |
|---|---|
| FFmpeg | n8.1.3（`FFMPEG_VERSION "8.1.3"`，libavutil 60.26.103） |
| x265 | master `b81f650`（2026-06-23），`X265_BUILD 216` |
| lame | 4.0（`PACKAGE_VERSION='4.0'`） |
| x264 | 未动（stable `eaa68fa`） |
| AAR | **12,605,392 B**（基线 12,625,191 B，**−19,799 B / −0.16%**，远在 ±5% 内） |
| `.so` 版本 | `libavutil.so` / `libffmpegkit.so` 内均含字符串 `8.1.3` |
| AAR 内容 | 10 个 `.so` + `classes.jar`，`libc++_shared.so` 已 strip（1,794,776 → 1,292,904 B） |
| 版本号 | `versionCode 240813` / `versionName "8.1.3"` / `FFMPEG_KIT_VERSION "8.1.3"` |
| 三方合并 | 43 文件 / 14 需处理 / **0 冲突**（与方案预测一致） |

构建耗时明细：x265 约 2 min、lame 约 2 min、FFmpeg configure 约 4 min + make 约 2 min、JNI 36 s、AAR 约 1 min。

### 9.2 方案没预见的 4 个问题（均已修，需记住）

| # | 现象 | 根因 | 处置 |
|---|---|---|---|
| 1 | `ld.lld: error: undefined symbol: android_binder_threadpool_init_if_required` | `fftools_ffmpeg.c` 里该调用被 `#if CONFIG_MEDIACODEC` 包着。**历史上 config.h 是精简版（mediacodec=0），整段被预处理掉**，所以从没暴露；本次修正 config.h 同源后 `CONFIG_MEDIACODEC=1`，缺口立刻显现。而 FFmpeg 的 `compat_objs` 只进可执行文件，不进任何 `libav*.so` | 镜像 `compat/android/{binder.c,binder.h}` 到 cpp/（保持相对 include，`fftools_ffmpeg.c` 零改动），Android.mk 加一条；并补 `<android/api-level.h>`（上游靠隐式声明，`-Werror` 下必挂）。详见 `ffmpeg-modifications.md` #6 |
| 2 | `-Werror,-Wunused-function`：`android_binder_threadpool_init` 未被使用 | `Application.mk` 是 `APP_PLATFORM := android-21`，而 FFmpeg 用 API 24 编译 → `#if __ANDROID_API__ >= 24` 分支失效 | `APP_PLATFORM` 改 `android-24`（与 minSdk 24 一致）；顺手删掉误设的 `-DFFMPEG_KIT_LTS`（它让 `AbiDetect.isNativeLTSBuild()` 错报 true） |
| 3 | Gradle：`Unsupported class file major version 69` | 宿主 `JAVA_HOME=D:\dev\jdk-25`，Gradle 8.10.2 的 Groovy 解析不了 Java 25 字节码 | `android/gradle.properties` 加 `org.gradle.java.home=D:/dev/jdk-17.0.2` |
| 4 | lame 每次构建都重编 | 跳过判据检查 `pkgconfig/mp3lame.pc`，但该文件**从来不存在**（lame 4.0 生成的是 `lame.pc`） | 判据改为只看 `libmp3lame.a` |

### 9.3 与方案预测的偏差

| 预测 | 实际 | 结论 |
|---|---|---|
| 7 个 fftools 文件变更、+95/−41 | 7 个文件、144 行 | ✅ 基本吻合（`ffmpeg_demux.c` 96 行是最大头） |
| 三方合并 0 冲突 | 0 冲突 | ✅ |
| AAR ±5% | −0.16% | ✅ |
| 工时 3 h | 26 min（含文档） | ✅ 优于预估，`/mnt/d` 9p 未成为瓶颈 |
| 风险表里的「NDK r27d + `-Werror` 新告警」 | 命中了，但来自 `binder.c` 而非 FFmpeg 本体 | ⚠ 已修 |
| 风险表里的「内部头文件漏回填」 | 未发生（已脚本化并断言） | ✅ |

### 9.4 本次新增的基础设施

| 文件 | 作用 |
|---|---|
| `build_scripts/port_fftools.py` | fftools 三方合并（flatten + 15 个 include 改名 + `git merge-file --diff3`），下次升级一条命令 |
| `build_scripts/backfill_ffmpeg_headers.sh` | 20 个内部头回填 + **config.h 同源断言**（含 `mediacodec` 必须为 1、`disable-everything` 必须为 0） |
| `build-cli-binary-ndk-r27d.sh` | 轨道 B 合并版（原 `D:\workspace\ffmpeg-8.1-android-bin` 两个脚本），修掉 NDK r25b/路径/`PKG_CONFIG_PATH` 三处问题 |
| `AGENTS.md` | 原 `CLAUDE.md`，补全开发环境（WSL/NDK/JDK/Gradle/路径映射/硬性约束） |

### 9.5 尚未完成（需真机）

§5 的 10 项回归清单全部未跑，其中第 7、8 项（ffprobe 元信息、help/错误输出 + 连续执行 10 次）最关键——
它们验证的是**本地改造在合并后是否存活**，而不是 8.1.3 本身。

回退路径：
```bash
# A. 应用侧（最快）
# app/build.gradle.kts 改回 files("libs/ffmpeg-kit-8.1.aar")

# B. 库侧
rm -rf prebuilt/android-arm64 && mv prebuilt/android-arm64-8.1-backup prebuilt/android-arm64

# C. 外部库
rm -rf src/lame && mv src/lame-3.100-backup src/lame   # lame 回 3.100
# x265 回 7b3d1f5：cd src/x265 && git checkout -f 7b3d1f5
```

---

## 附录：本次实测证据索引

| 结论 | 取证命令/来源 |
|---|---|
| 8.1.3 为正式发布 | `curl -sIL https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz` → `HTTP/2 200`，11,732,548 B，2026-09-21 |
| 补丁级、零 API 删除 | `gh api repos/FFmpeg/FFmpeg/contents/{lib}/version_major.h?ref=n8.1\|n8.1.3`，FF_API 宏数 0/9/5/4 一致 |
| fftools 仅 7 文件 | `gh api repos/FFmpeg/FFmpeg/compare/n8.1...n8.1.3`，filter `fftools/` → +95/−41 |
| 本地改造规模 | `diff --strip-trailing-cr -u src/ffmpeg/fftools/X.c cpp/fftools_X.c` |
| 无 `-re`/`readrate`/`disposition` | `grep -rn` StreamClip `app/src/main/java` |
| `-t` 唯一用法 | `FFmpegService.kt:316` `append("-t $durationSec ")` |
| 脚本路径失效 | `grep -n BASEDIR build-*.sh` → `/mnt/d/nili/3rd_party_projects/...` |
| 内部头文件回填清单 | `scripts/android/ffmpeg.sh` 第 511–545 行（20 个 `overwrite_file` + 6 个 `mkdir`） |
| x264 上游停更 | `gh api repos/mirror/x264/commits?sha=master` → 最后 2024-09-17；stable 最后 2023-10-01 |
| x264 master 与本地差异 | `git diff --stat HEAD origin/master -- common/aarch64/ common/arm/` → 47 文件 +7241/−2150 |
| x265 最新 master | `git ls-remote https://bitbucket.org/multicoreware/x265_git.git refs/heads/master` → `b81f650`（2026-06-23） |
| x265 BUILD 号对照 | 各 tag 的 `source/CMakeLists.txt` → 3.4=192 / 3.6=209 / 4.0=212 / 4.2=216 |
| lame 4.0 真实存在 | `curl -sIL .../lame/4.0/lame-4.0.tar.gz` → `200`，1,496,810 B，Last-Modified 2026-07-11 |
| lame 4.0 强制 mpg123 | 实测 `./configure --disable-frontend --disable-gtktest --with-pic` → `configure: error: no, libmpg123 not found`（exit 1）；加 `--disable-decoder` 后 exit 0 |
| lame 4.0 API 兼容 | `grep -c lame_set_VBR_quality include/lame.h` → 1（签名未变） |
| FLAC 内置编码器 | `libavcodec/flacenc.c` 存在；`configure:3138 flac_encoder_select="bswapdsp lpc"` |
| APE 无编码器 | `ls libavcodec/apeenc.c` → 不存在；`configure` 仅 `ape_decoder_select` |
| fdk-aac 3.0.0 | `gh api repos/mstorsjo/fdk-aac/tags` → v3.0.0（2026-10-11）；ChangeLog 首条 "Including a separate new library, fdk-xhe-aac" |
| 内置 aac 在 9.0 的改动 | `commits?path=libavcodec/aacenc.c&sha=n9.0.2` → 全为多声道 PCE/通道布局修复 |
