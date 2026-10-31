# FFmpeg Source Modifications

This document tracks all modifications made to FFmpeg source files in this fork. These changes are applied in the FFmpeg Kit JNI layer (`android/ffmpeg-kit-android-lib/src/main/cpp/`), NOT to the original FFmpeg source (`src/ffmpeg/`).

## Architecture

FFmpeg Kit copies specific FFmpeg source files into its JNI directory and adds an `fftools_` prefix. These copies are what get compiled into `libffmpegkit.so`. Our modifications only touch these copies.

```
src/ffmpeg/                          # Original FFmpeg 8.1 source (untouched)
android/ffmpeg-kit-android-lib/src/main/cpp/
  fftools_ffprobe.c                  # Modified: removed log_callback_help override
  fftools_cmdutils.c                 # Modified: log_callback_help + help functions → stderr
  fftools_opt_common.c               # Modified: removed log_callback_help overrides, ALL printf → av_log (108 calls)
  fftools_ffmpeg_mux.c               # Modified: SDP output → av_log
  fftools_tw_stdout.c                # Modified: stdout writer → av_log redirect
  fftools_*.c                        # Other fftools (unmodified copies)
  ffprobekit.c                       # JNI bridge (unmodified)
  ffmpegkit.c                        # JNI bridge (unmodified)
```

---

## Background: How Native Output Reaches Java

The native-to-Java bridge (`ffmpegkit.c`) sets `av_log_set_callback(ffmpegkit_log_callback_function)` on `JNI_OnLoad`. All `av_log()` calls are routed through this callback to the Java layer. The special level `AV_LOG_STDERR` is always forwarded regardless of log level settings.

**Key rule:** Any C code that writes to `stdout` (via `printf`, `fprintf(stdout,...)`, etc.) is **invisible** to the Java layer. Only `av_log()` calls reach Java.

---

## Modification #1: ffprobe stdout → av_log Redirect

### Problem

ffprobe writes JSON output to **stdout** via `printf()`. The Java layer (`FFmpegKitConfig.getMediaInformationExecute()`) only reads from the **av_log callback system** at `AV_LOG_STDERR` level. These are two completely separate output channels.

On Android, native stdout typically goes to logcat or nowhere — it is not routed into the Java-side log queue.

**Result:** ffprobe succeeds but returns empty metadata because the JSON never reaches the Java parser.

### Call Chain (Before Fix)

```
FFprobeKit.getMediaInformation(path)
  → JNI → ffprobe_execute()
    → JSON written to stdout via printf()     ← lost on Android
    → av_log produces no messages (-v error)   ← Java reads from here
  → Java collects AV_LOG_STDERR logs → empty
  → MediaInformationJsonParser.fromWithError("") → JSONException
  → mediaInformation = null
```

### Fix

**File modified:** `fftools_tw_stdout.c`

Replaced the stdout writer (`avtextwriter_stdout`) with an av_log writer (`avtextwriter_avlog`). The new writer:

1. Buffers characters until a newline is encountered
2. Flushes complete lines via `av_log(NULL, AV_LOG_STDERR, "%s", line)`
3. Flushes remaining buffer on writer close (`uninit` callback)
4. Strips trailing `\n`/`\r` before logging (av_log adds its own)

The function name `avtextwriter_create_stdout()` is preserved for ABI compatibility — callers don't need changes.

### Key Design Decisions

- **Buffer size:** 4096 bytes — large enough for typical JSON lines, small enough for stack
- **Log level:** `AV_LOG_STDERR` — matches what `FFmpegKitConfig.getMediaInformationExecute()` filters for
- **No modification to `fftools_ffprobe.c`** — the fix is isolated to the output writer
- **No modification to Java layer** — the existing `getAllLogs(AV_LOG_STDERR)` mechanism works as-is

### Post-Fix Call Chain

```
FFprobeKit.getMediaInformation(path)
  → JNI → ffprobe_execute()
    → JSON written via avlog_w8/avlog_put_str
    → buffered, flushed line-by-line via av_log(AV_LOG_STDERR)
  → Java collects AV_LOG_STDERR logs → JSON content
  → MediaInformationJsonParser.fromWithError(json) → success
  → mediaInformation with metadata
```

---

## Modification #2: Remove log_callback_help Override (fftools_ffprobe.c, fftools_opt_common.c)

### Problem

Several functions call `av_log_set_callback(log_callback_help)` which replaces the JNI bridge callback with `log_callback_help` — a function that writes directly to stdout via `vfprintf(stdout, ...)`. This completely bypasses the Java log capture mechanism.

**Affected paths:**
- `show_help_default_ffprobe()` — triggered by `-h`/`-help` on ffprobe
- `show_version()` — triggered by `-version`
- `show_buildconf()` — triggered by `-buildconf`
- `show_help()` — triggered by `-help` on ffprobe

After these functions execute, the JNI callback is **never restored**, so all subsequent `av_log` calls also go to stdout.

### Fix

**Files modified:** `fftools_ffprobe.c`, `fftools_opt_common.c`

Removed all `av_log_set_callback(log_callback_help)` calls. Now av_log output goes through the JNI callback and reaches the Java layer.

**Help text output** (from `show_help_options`, `show_help_children`) was changed from `printf()` to `fprintf(stderr, ...)` so it still appears in logcat for debugging.

### Key Design Decisions

- **No callback override** — the JNI callback is never replaced, ensuring all av_log output reaches Java
- **Help text to stderr** — debug help text goes to stderr (visible in logcat), while structured data (option descriptions from `av_opt_show2`) goes through av_log to Java
- **Consistent across all callers** — applied to `show_version`, `show_buildconf`, `show_help`, and `show_help_default_ffprobe`

---

## Modification #3: Help Display Functions → stderr (fftools_cmdutils.c)

### Problem

`show_help_options()` and `show_help_children()` used `printf()` to display help text. On Android, stdout is not captured by the Java layer.

### Fix

**File modified:** `fftools_cmdutils.c`

- `log_callback_help()`: `vfprintf(stdout, ...)` → `vfprintf(stderr, ...)`
- `show_help_options()`: all `printf()` → `fprintf(stderr, ...)`
- `show_help_children()`: `printf("\n")` → `fprintf(stderr, "\n")`

---

## Modification #4: SDP Output → av_log (fftools_ffmpeg_mux.c)

### Problem

When ffmpeg creates an RTP muxer without `-sdp_filename`, the SDP description is printed directly to stdout via `printf("SDP:\n%s\n", sdp)`. This is invisible to the Java layer.

### Fix

**File modified:** `fftools_ffmpeg_mux.c`

Changed `printf("SDP:\n%s\n", sdp)` + `fflush(stdout)` to `av_log(NULL, AV_LOG_STDERR, "SDP:\n%s\n", sdp)`.

---

## Modification #5: All printf → av_log (fftools_opt_common.c)

### Problem

`fftools_opt_common.c` contained 103 `printf()` calls across many functions: `show_license()`, `print_codec()`, `show_formats_devices()`, `show_filters()`, `show_bsfs()`, `show_protocols()`, `show_pix_fmts()`, `show_layouts()`, `show_codecs()`, `show_decoders()`, `show_encoders()`, etc. All of these wrote to stdout, invisible to the Java layer.

### Fix

**File modified:** `fftools_opt_common.c`

Bulk-replaced all 103 `printf(` calls with `av_log(NULL, AV_LOG_STDERR, `. The `PRINT_CODEC_SUPPORTED` macro was also converted (part of the same bulk replacement).

### Verified Clean

After the fix: 0 `printf()` calls remaining, 108 `av_log()` calls (including the pre-existing ones in `PRINT_LIB_INFO` macro).

---

## Modification #6: 补编 `compat/android/binder.c`（FFmpeg 8.1.3 起必需）

### Problem

`fftools_ffmpeg.c` 里有一段：

```c
#if CONFIG_MEDIACODEC
    android_binder_threadpool_init_if_required();
#endif
```

该函数定义在 FFmpeg 的 `compat/android/binder.c`，而 FFmpeg 的 `compat_objs` **不会**进任何 `libav*.so`
（只进 `ffmpeg`/`ffprobe` 可执行文件，而我们用 `--disable-programs`）。

历史上之所以没暴露：`prebuilt/.../include/config.h` 内嵌的是**精简版二进制**的 configure（含
`--disable-everything`、无 mediacodec），`CONFIG_MEDIACODEC` 为 0 → 整段被预处理掉。

2026-10-31 修正 config.h 同源问题后，`CONFIG_MEDIACODEC` 变成 1，链接立刻报：

```
ld.lld: error: undefined symbol: android_binder_threadpool_init_if_required
>>> referenced by fftools_ffmpeg.c:1076 :(ffmpeg_execute)
```

### Fix（第一轮：补编）

1. 把上游 `compat/android/{binder.c,binder.h}` **原样镜像**到 `android/ffmpeg-kit-android-lib/src/main/cpp/compat/android/`
   —— 保留 `#include "compat/android/binder.h"` 的相对路径，`fftools_ffmpeg.c` **零改动**，升级时不会被合并冲掉
2. 在 `compat/android/binder.c` 补 `#include <android/api-level.h>`
   —— 上游靠隐式声明使用 `android_get_device_api_level()`，JNI 层用 `-Werror` 编译会直接失败
3. `android/jni/Android.mk` 的 `MY_SRC_FILES` 追加 `compat/android/binder.c`

### Fix（第二轮：必须改函数体，否则 App 内必崩）

「原样镜像」是错的。真机（Android 17 / API 37）上**每一次 ffmpeg 执行都 SIGABRT**：

```
Fatal signal 6 (SIGABRT) in tid … (pool-7-thread-1)
Abort message: 'Binder threadpool cannot be shrunk after starting'
#04 /system/lib64/libbinder.so     android::ProcessState::setThreadPoolMaxThreadCount(unsigned long)+92
#05 /system/lib64/libbinder_ndk.so ABinderProcess_setThreadPoolMaxThreadCount+48
#06 base.apk!libffmpegkit.so       android_binder_threadpool_init_if_required+228
#07 base.apk!libffmpegkit.so       ffmpeg_execute+304
```

根因是上游 `android_binder_threadpool_init()` 里的这一句：

```c
set_thread_pool_max(THREAD_POOL_SIZE /* = 1 */);
```

而框架侧 `ProcessState::setThreadPoolMaxThreadCount()` 带一条断言：

```cpp
LOG_ALWAYS_FATAL_IF(mThreadPoolStarted && maxThreads < mMaxThreads,
                    "Binder threadpool cannot be shrunk after starting");
```

上游这套逻辑是给 **ffmpeg 独立可执行文件**写的：那种进程里池尚未启动，设上限合法。
但 `libffmpegkit.so` 是嵌在 App 里跑的 —— ART 在进程启动时就已经开了 binder 池，而且上限比 1 大，
此时传 1 就构成「缩容」，断言直接 abort。**旧 8.1 AAR 的 `libffmpegkit.so` 里没有任何
`android/binder:` 字符串（即压根没编这段），所以老版本不崩、8.1.3 崩**。

修法：函数体里**删掉 `setThreadPoolMaxThreadCount` 整段**，只保留幂等的 `startThreadPool()`
（池已启动时直接返回，不碰上限）；`fftools_ffmpeg.c` 的调用点保持不动。
上游想解决的 Android 15+ MediaCodec 问题，在 App 场景下由系统已启动的池天然满足。

⚠️ 两份文件必须**逐字一致**：
`ffmpeg-8.1.3/compat/android/binder.c`（源）↔ `cpp/compat/android/binder.c`（JNI 侧镜像）。
镜像文件额外多一行 `#include <android/api-level.h>`。

### 为什么保留调用点而不删

FFmpeg 加它是为了修 **Android 15（API 35）起的 MediaCodec 问题**。函数内部用
`dlopen("libbinder_ndk.so")` + `dlsym` 而不是真链接，缺失时只打一条 warning，因此不引入新的
`NEEDED` 依赖，老机型无副作用。保留调用点可以让升级时 fftools 三方合并零冲突。

### 附带修正：`android/jni/Application.mk`

| 项 | 原值 | 新值 | 原因 |
|---|---|---|---|
| `APP_PLATFORM` | `android-21` | **`android-24`** | JNI 按 API 21 编、FFmpeg 按 API 24 编，两者不一致；且 `binder.c` 的 `__ANDROID_API__ >= 24` 分支会失效 |
| `-DFFMPEG_KIT_LTS` | 有 | **删除** | 本 fork 不是 LTS，该宏让 `AbiDetect.isNativeLTSBuild()` 错报 `true`（`ffmpegkit_abidetect.c:128`） |
| `FFMPEG_KIT_BUILD_DATE` | `20260507` | `20261031` | 由 `ffmpegkit.c:887` 打印 |

---

## 版本升级时如何维护这些改动

不再人工比对。用 `build_scripts/port_fftools.py` 做三方合并：

```bash
# 1) 只出报告
python3 build_scripts/port_fftools.py \
  --new  /mnt/d/3rd-party-projects/ffmpeg-<新版>/fftools \
  --base /mnt/d/3rd-party-projects/ffmpeg-<旧版>/fftools

# 2) 确认后写盘
python3 build_scripts/port_fftools.py --new ... --base ... --apply
```

> `--base` 指向**上一版发布源码**。旧的 `ffmpeg-8.1` 目录已于 2026-10-31 删除（它是单提交快照、混入构建产物），
> 需要时从 `https://ffmpeg.org/releases/ffmpeg-<ver>.tar.xz` 现解一份到 `D:\3rd-party-projects\`。

- 三方定义：**ours = 本地 `fftools_*` 拷贝**，base = 旧版上游，theirs = 新版上游
- 本地无改动的文件直接跟随上游；有改动的走 `git merge-file --diff3`，冲突留标记
- 脚本同时做 flatten（加 `fftools_` 前缀）与 15 个头文件的 include 改名
- **`compat/android/*` 不在脚本管辖范围**，需在上游结构变化时手工确认
- ⚠️ **`compat/android/binder.c` 每次升级都要重新删掉 `ABinderProcess_setThreadPoolMaxThreadCount(1)`**
  （详见 §6 的"第二轮"与 `ffmpeg-build.md` §3.8）。新版源码覆盖该文件后补丁必丢，漏了就是 App 内必崩

---

## Adding New Modifications

When modifying FFmpeg source in this fork:

1. **Document it here** — add a new numbered section with Problem/Fix/Design Decisions
2. **Modify only the `fftools_*.c` copies** in `android/ffmpeg-kit-android-lib/src/main/cpp/`
3. **Never modify** files under `src/ffmpeg/`（现在是 `../ffmpeg-8.1.3` 的软链）
4. **Test the build** — JNI 用 `build-jni-ndk-r27d.sh`，AAR 用 `build-aar-ndk-r27d.sh`
5. **Update this file** before committing

