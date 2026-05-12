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

## Adding New Modifications

When modifying FFmpeg source in this fork:

1. **Document it here** — add a new numbered section with Problem/Fix/Design Decisions
2. **Modify only the `fftools_*.c` copies** in `android/ffmpeg-kit-android-lib/src/main/cpp/`
3. **Never modify** files under `src/ffmpeg/`
4. **Test the build** — run `build_aar.sh` to verify compilation
5. **Update this file** before committing
