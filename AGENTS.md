# AGENTS.md — ffmpeg-kit fork 开发环境与协作约定

> 本文件面向在此仓库工作的 AI agent / 开发者：说明**怎么构建**、**环境长什么样**、**哪些坑不能踩**。
> 权威构建细节见 [`docs/ffmpeg-build.md`](docs/ffmpeg-build.md)（唯一事实来源），本文只做索引 + 环境快照 + 行为约束。
> 最后更新：2026-10-31

---

## 1. 项目是什么

`pisces312/ffmpeg-kit` —— 自编译的 Android **arm64-v8a** FFmpeg Kit 发行包（AAR），基于 FFmpeg 8.1（正在升级到 8.1.3），
含 GPL 组件（x264 / x265 / lame）与 MediaCodec 硬编硬解。消费方是 StreamClip（`D:\my-projects\StreamClip`）。

- 包名：`com.arthenica.ffmpeg-kit`
- 产物：`android/ffmpeg-kit-android-lib/build/outputs/aar/ffmpeg-kit-release.aar`
- 交付名：`ffmpeg-kit-8.1.aar`（12,625,191 B，基线）
- 仅 `arm64-v8a` 单 ABI

## 2. 文档索引

| 文档 | 内容 |
|---|---|
| [docs/ffmpeg-build.md](docs/ffmpeg-build.md) | **构建总纲（唯一事实来源）**：环境基线、两条轨道、完整 configure、编码器取舍、踩坑登记 |
| [docs/ffmpeg-8.1.3-rebuild-plan.md](docs/ffmpeg-8.1.3-rebuild-plan.md) | 8.1.3 施工方案：外部库决策、Step 0–7、回归清单、回退路径 |
| [docs/ffmpeg-modifications.md](docs/ffmpeg-modifications.md) | 本 fork 对 FFmpeg 源码的全部改动 |
| [docs/index.md](docs/index.md) | 文档总览 |
| [docs/native-memory-check-guide.md](docs/native-memory-check-guide.md) | native 内存排查方法 |
| [docs/2026-05-14-cppcheck-report-summary.md](docs/2026-05-14-cppcheck-report-summary.md) | cppcheck 静态检查结论 |

---

## 3. 开发环境（2026-10-31 实测）

### 3.1 宿主与虚拟化

| 项 | 值 |
|---|---|
| 宿主 OS | Windows 11 26H2（build 26300），16 逻辑核 / 32 GB / RTX 5060 Laptop 8 GB |
| WSL2 发行版 | **Ubuntu 24.04.4 LTS**，内核 `6.18.54.1-microsoft-standard-WSL2` |
| WSL 用户 | `pisces312`（`/etc/wsl.conf` 里 `systemd=true`，默认用户已设） |
| WSL 资源配额 | `C:\Users\nili6\.wslconfig`：`memory=24GB`、`processors=12`、`swap=8GB` |
| WSL 实际可用 | 内存 23 GB、`nproc` = **12**（构建并发以此为准） |
| 磁盘 | `/` 1007 GB（已用 59 GB）；`/mnt/d` 792 GB（已用 584 GB，**余 209 GB**） |

> 构建必须在 **WSL** 内跑。Windows 原生 NDK 的 clang 是 `.exe`，`configure`/`make`/`pkg-config` 链路跑不通。

### 3.2 工具链版本

| 工具 | 版本 | 备注 |
|---|---|---|
| NDK | `~/android-ndk-r27d` = **27.3.13750724** | Linux 版，轨道 A/B 统一使用 |
| cmake | 3.28.3 | x265 / cpu-features 用 |
| make | GNU Make 4.3 | |
| pkg-config | 1.8.1 | 脚本内有 fallback wrapper（写 `/usr/local/bin/pkg-config`，需 sudo） |
| python3 | 3.12.3 | `build_scripts/*.py` 用 |
| git | 2.43.0 | |
| JDK（WSL） | OpenJDK **21.0.12.1** (Ubuntu 24.04) | 仅 shell 工具用，Gradle 不走这个 |
| JDK（Gradle） | **`D:\dev\jdk-17.0.2`** | 宿主 `JAVA_HOME=D:\dev\jdk-25`，Gradle 8.10.2 解析不了 Java 25 字节码（`Unsupported class file major version 69`）。已在 `android/gradle.properties` 用 `org.gradle.java.home` 钉住 |
| Gradle | **8.10.2**（腾讯云镜像） | `android/gradle/wrapper/gradle-wrapper.properties` |
| AGP | **8.7.3** | `android/build.gradle` |
| buildTools | 35.0.0 | Windows 侧 Android SDK |
| compileSdk / minSdk / targetSdk | 33 / 24 / 33 | `android/ffmpeg-kit-android-lib/build.gradle` |
| `ndkVersion`（Gradle 声明） | 25.1.8937393 | **惰性字段**：本模块无 `externalNativeBuild`，Gradle 不会真的用它，无需安装 |
| `APP_PLATFORM`（ndk-build） | **android-24** | 与 FFmpeg 的 `aarch64-linux-android24-clang` 及 minSdk 24 对齐（原为 21，见 §5 坑 10） |
| ABI / API level | `arm64-v8a` / `android-24` | `aarch64-linux-android24-clang` |

### 3.3 路径映射

| Windows | WSL | 说明 |
|---|---|---|
| `D:\3rd-party-projects\ffmpeg-kit` | `/mnt/d/3rd-party-projects/ffmpeg-kit` | **本仓库** |
| `D:\3rd-party-projects\ffmpeg-8.1` | `/mnt/d/3rd-party-projects/ffmpeg-8.1` | FFmpeg 8.1 源码（**单提交快照**，非上游 git 仓库，另有软链 `~/ffmpeg-8.1` 指向它） |
| （规划中）`D:\3rd-party-projects\ffmpeg-8.1.3` | `/mnt/d/3rd-party-projects/ffmpeg-8.1.3` | 8.1.3 源码（tarball 解压，保留 8.1 作回退源） |
| `D:\my-projects\StreamClip` | `/mnt/d/my-projects/StreamClip` | 消费方 App |

> 仓库根目录在脚本里**已改为自动推导**（`BASH_SOURCE`），不再写死。历史上的 `/mnt/d/nili/3rd_party_projects/...` 是废弃路径。

### 3.4 源码与外部库

| 组件 | 位置 | 版本 |
|---|---|---|
| FFmpeg | `src/ffmpeg`（软链或链接到 `$FFMPEG_SRC`） | n8.1 → 目标 n8.1.3 |
| x264 | `src/x264` | stable @ `eaa68fa`（2023-01-28），`X264_BUILD 164` |
| x265 | `src/x265` | master @ `7b3d1f5`（2026-05-04），`X265_BUILD 216`（= 4.2） |
| lame | `src/lame` | 3.100 → 目标 **4.0** |
| cpu-features | `src/cpu-features` | NDK compat 库 |

`src/` 共约 370 MB，**未纳入版本库**（见 `.gitignore`）。

---

## 4. 构建流程

### 4.1 轨道 A：AAR（生产路径，三步）

```bash
cd /mnt/d/3rd-party-projects/ffmpeg-kit

# 1) 外部库 + FFmpeg 共享库 → prebuilt/android-arm64/ffmpeg
./build-ffmpeg-ndk-27d.sh                 # 全量；FORCE_FFMPEG=1 只重编 FFmpeg 本体

# 2) JNI 移植层 (ndk-build) + 拷贝 .so → android/libs/arm64-v8a
./build-jni-ndk-r27d.sh                   # --debug 保留符号、关优化

# 3) Gradle 打包 + llvm-strip → AAR
./build-aar-ndk-r27d.sh                   # --debug 跳过 strip
```

第 3 步内部用 `cmd.exe /c gradlew.bat` 调 **Windows 侧 Gradle**（build-tools 是 Windows 二进制，WSL 里跑不了）。

### 4.2 轨道 B：CLI 静态二进制（备用 / 调试）

```bash
./build-cli-binary-ndk-r27d.sh minimal    # 8.8 MB，按清单裁剪（默认）
./build-cli-binary-ndk-r27d.sh full       # 15.2 MB，全量组件
```

产出在 `out/cli/{minimal,full}/bin/`。**不要打包进 App**：静态二进制拿不到 `JavaVM`，mediacodec 不可用。
⚠ 该脚本会 `make distclean` 清掉轨道 A 的 `config.h` → **先 AAR 后 CLI**。

### 4.3 辅助脚本

| 脚本 | 用途 |
|---|---|
| `build-cpu-features-ndk-27d.sh` | 编 `libndk_compat.a`（NDK 兼容层） |
| `check-aar-ffmpeg-version.sh` | 校验 AAR 内的 FFmpeg 版本 / SONAME |
| `build_scripts/port_fftools.py` | **fftools 移植**：flatten + include 改名 + 三方合并（升级 FFmpeg 版本时用） |
| `build_scripts/copy_textformat.py` | fftools 子目录 flatten |
| `build_scripts/fix_includes.py` | flatten 后的 include 改写 |
| `build_ffmpeg_full.sh` / `build_aar.sh` | **旧脚本，已弃用**，仅留作参考 |
| `android.sh` / `ios.sh` / `macos.sh` / ... | 上游官方脚本，**本 fork 未使用** |

### 4.4 fftools 移植（升级 FFmpeg 版本时）

```bash
# 先只出报告（不写盘）
python3 build_scripts/port_fftools.py \
  --new  /mnt/d/3rd-party-projects/ffmpeg-8.1.3/fftools \
  --base /mnt/d/3rd-party-projects/ffmpeg-8.1/fftools

# 确认后写盘
python3 build_scripts/port_fftools.py --new ... --base ... --apply
```

三方合并的三方是：**ours = 本地 `fftools_*` 拷贝**，base = 旧版上游，theirs = 新版上游。
纯 flatten 变更直接跟随上游；含本地改造的走 `git merge-file --diff3`，冲突会留标记。
2026-10-31 实测 n8.1→n8.1.3：43 个文件、14 个需处理、**0 冲突**。

---

## 5. 硬性约束（踩过的坑，别再踩）

1. **只改 `fftools_*` 拷贝，不改上游原文**
   移植层在 `android/ffmpeg-kit-android-lib/src/main/cpp/`。上游源码保持干净，方便下次升级做三方合并。
   `src/ffmpeg` 现在是指向 `../ffmpeg-8.1.3` 的软链，**它不是可编辑副本**。

2. **`make install` 不装 FFmpeg 内部头文件**
   `config.h`、`libavutil/thread.h`、`libavformat/network.h` 等 20 个必须回填到
   `prebuilt/android-arm64/ffmpeg/include/`，否则 JNI 编译报 `No such file`。**已踩两次（2026-05-13、2026-08）**
   → 现用 `build_scripts/backfill_ffmpeg_headers.sh`，带同源断言。

3. **`config.h` 必须与 `.so` 同源**
   旧仓库里的 `include/config.h` 内嵌的是**精简版二进制** configure（含 `--disable-everything`），
   而同目录 `.so` 是 AAR 全量配置。这不只是理论问题：`CONFIG_MEDIACODEC` 因此恒为 0，
   `fftools_ffmpeg.c` 里 `#if CONFIG_MEDIACODEC` 包着的 binder 初始化从未被编译进来。
   **修正 config.h 后 JNI 链接会立刻报 `android_binder_threadpool_init_if_required` 未定义，属预期。**

4. **`compat/android/binder.c` 必须单独编进 JNI**
   FFmpeg 的 `compat_objs` 只进可执行文件（我们 `--disable-programs`），不进任何 `libav*.so`。
   `cpp/compat/android/` 是上游镜像，`Android.mk` 的 `MY_SRC_FILES` 必须包含 `compat/android/binder.c`。
   该目录**不受 `port_fftools.py` 管辖**，上游结构变化时需手工同步。

5. **`.pc` 文件的 `prefix=` 必须与真实路径一致**
   `pkgconfig/*.pc` 里若残留 `/mnt/d/nili/...`，`configure` 会把 `-I/-L` 指到空目录并报 `x264 not found`。

6. **x265 必须 `ENABLE_ASSEMBLY=0`**
   NDK 交叉编译汇编报 `unknown target CPU 'armv8-a'`。同时需要 `--extra-libs="-lm -lc++"`（x265 是 C++ 库）。

7. **lame 4.0 必须加 `--disable-decoder`**
   4.0 把 mpg123 从可选改成强制依赖，不加该参数直接 `configure: error: no, libmpg123 not found`。
   另：lame 4.0 生成的是 `lame.pc`，**不是** `mp3lame.pc`——用它做跳过判据会导致每次重编（已修）。

8. **x264 的 `--cross-prefix` 是 `$TOOLCHAIN/bin/llvm-`**
   不是 `aarch64-linux-android-`。

9. **`APP_PLATFORM` 必须与 FFmpeg 的 API 一致（24）**
   原为 `android-21`：JNI 按 21 编、FFmpeg 按 24 编，且 `binder.c` 的 `#if __ANDROID_API__ >= 24`
   分支会失效（`android_get_device_api_level` 不可用）→ `-Werror,-Wunused-function`。
   同一文件里 `-DFFMPEG_KIT_LTS` 已删：它让 `AbiDetect.isNativeLTSBuild()` 错报 true。

10. **Gradle 必须用 JDK 17，不能用宿主 `JAVA_HOME`（JDK 25）**
    Gradle 8.10.2 的 Groovy 解析不了 Java 25 字节码 → `Unsupported class file major version 69`，
    构建脚本在 semantic analysis 阶段就挂。已在 `android/gradle.properties` 固定。

11. **不要升级到 FFmpeg 9.x**（当前决策）
    9.0 对本项目零功能收益，且 movenc 时间基变更会改变裁剪/合并的时长与时间戳表现。理由与证据见
    `docs/ffmpeg-8.1.3-rebuild-plan.md`。

12. **`src/` 不进版本库**
    约 258 MB（含 lame 3.100 备份）。`git status` 里出现 `?? src/*` 属正常。

---

## 6. 现有源码改动（fork 特有）

`android/ffmpeg-kit-android-lib/src/main/cpp/` 下，**7 个 fftools 文件含实质改造 + 1 个 compat 镜像**：

| # | 文件 | 改动 |
|---|---|---|
| 1 | `fftools_tw_stdout.c` | ffprobe 的 JSON 输出从 `printf`/stdout 整体改走 `av_log`（108 行重写） |
| 2 | `fftools_opt_common.c` | 103 处 `printf` → `av_log`；移除 `av_log_set_callback(log_callback_help)` |
| 3 | `fftools_cmdutils.c` | `log_callback_help` / `show_help_*` 输出改 stderr |
| 4 | `fftools_ffmpeg.c` | 注入 `report_callback` 钩子；`ffmpeg_cleanup` 计数器复位（连续执行不崩的关键） |
| 5 | `fftools_ffmpeg_mux.c` | SDP 输出改 `av_log` |
| 6 | `fftools_ffprobe.c` | 移除 `av_log_set_callback(log_callback_help)` |
| 7 | `fftools_graphprint.c` | 输出改 `av_log`，include 改名 |
| 8 | `compat/android/{binder.c,binder.h}` | 上游镜像 + 补 `<android/api-level.h>`；解决 `android_binder_threadpool_init_if_required` 链接缺口（Android 15 MediaCodec 死锁修复） |

其余 38 个 `fftools_*` 文件是纯 flatten（加前缀 + include 改写）。逐条细节见 [`docs/ffmpeg-modifications.md`](docs/ffmpeg-modifications.md)。

---

## 7. 当前状态

- **已完成：FFmpeg n8.1 → n8.1.3 重建**（2026-10-31）
  - AAR `12,605,392 B`（基线 12,625,191 B，−0.16%）；`versionCode 240813` / `versionName "8.1.3"`
  - 同批升级 x265 master `b81f650`、lame 4.0
  - StreamClip 已切到 `libs/ffmpeg-kit-8.1.3.aar`，`:app:compileDebugKotlin` 通过
  - **真机 10 项回归未跑**（见 `docs/ffmpeg-8.1.3-rebuild-plan.md` §5）
- `main` @ `6635c31`；`ffmpeg-8.1` 分支 @ `4b944e0`（历史基线，含 MediaCodec 硬编首次提交）
- 已知未决：`AudioEncoder.kt:199` 用 `-c:a libopus` 但未编 libopus → 该导出选项必然失败（见重建方案 D1）
- 回退：AAR 侧改回 `libs/ffmpeg-kit-8.1.aar`；库侧 `mv prebuilt/android-arm64-8.1-backup prebuilt/android-arm64`

---

## 8. Git 约定

- remotes：`origin` = `git@github.com:pisces312/ffmpeg-kit`，`codeup` = `git@codeup.aliyun.com:.../pisces312/ffmpeg-kit.git`
- commit / push 前**先征得确认**
- 大文件（`.a` / `.so` / `src/`）不进库
