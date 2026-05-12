# FFmpegKit 8.1 Android AAR Build Plan

## Overview

Build `ffmpeg-kit` AAR for Android `arm64-v8a` based on FFmpeg 8.1, using the existing `ffmpeg-kit-6.0` project as a starting point.

## Target Environment

| Item | Value |
|------|-------|
| FFmpeg source | `/home/pisces312/ffmpeg-8.1` |
| Pre-built binaries | `/home/pisces312/android_build/arm64-v8a/bin` (ffmpeg, ffprobe) |
| Pre-built libs | `/home/pisces312/android_build/arm64-v8a/lib` (static .a files) |
| Pre-built includes | `/home/pisces312/android_build/arm64-v8a/include` |
| Working project | `/home/pisces312/ffmpeg-kit-8.1` (copied from ffmpeg-kit-6.0) |
| NDK | `/home/pisces312/android-ndk-r25b` |
| Architecture | arm64-v8a only |
| Libraries | Full build (GPL enabled, all external libs) |

## Key Differences: FFmpeg 6.0 → 8.1

### New fftools files in 8.1
- `ffmpeg_dec.c` (new: decoder logic split out from ffmpeg.c)
- `ffmpeg_enc.c` (new: encoder logic split out from ffmpeg.c)
- `ffmpeg_sched.c` / `ffmpeg_sched.h` (new: scheduler/threading)
- `ffmpeg_utils.h` (new: utility declarations)
- `ffplay_renderer.c` / `ffplay_renderer.h` (new: renderer)

### Removed/renamed fftools files
- `fftools_objpool.c/h` → removed (absorbed elsewhere)
- `fftools_opt_common.c/h` → `opt_common.c/h` (renamed, dropped fftools_ prefix)

### Header changes
- `ffmpeg.h` now includes `ffmpeg_sched.h`, `sync_queue.h`
- `cmdutils.h` replaces `fftools_cmdutils.h`
- New scheduler-based architecture with `ffmpeg_sched.h`

---

## Implementation Steps

### Step 1: Update Version Strings and Headers

**Files to modify:**

1. **`android/ffmpeg-kit-android-lib/src/main/cpp/ffmpegkit.h`**
   - Change `#define FFMPEG_KIT_VERSION "6.0"` → `"8.1"`

2. **`android/ffmpeg-kit-android-lib/build.gradle`**
   - Update `versionCode` and `versionName` (e.g., `versionName "8.1"`)

3. **`scripts/source.sh`**
   - Update ffmpeg source repo URL and tag to point to ffmpeg 8.1

### Step 2: Copy Fresh fftools Source from FFmpeg 8.1

Copy the following files from `/home/pisces312/ffmpeg-8.1/fftools/` to `android/ffmpeg-kit-android-lib/src/main/cpp/`:

**Files to copy (with fftools_ prefix added):**

| Source (ffmpeg 8.1) | Destination (ffmpeg-kit) |
|---------------------|--------------------------|
| `cmdutils.c` | `fftools_cmdutils.c` |
| `cmdutils.h` | `fftools_cmdutils.h` |
| `ffmpeg.c` | `fftools_ffmpeg.c` |
| `ffmpeg.h` | `fftools_ffmpeg.h` |
| `ffmpeg_dec.c` | `fftools_ffmpeg_dec.c` |
| `ffmpeg_demux.c` | `fftools_ffmpeg_demux.c` |
| `ffmpeg_enc.c` | `fftools_ffmpeg_enc.c` |
| `ffmpeg_filter.c` | `fftools_ffmpeg_filter.c` |
| `ffmpeg_hw.c` | `fftools_ffmpeg_hw.c` |
| `ffmpeg_mux.c` | `fftools_ffmpeg_mux.c` |
| `ffmpeg_mux.h` | `fftools_ffmpeg_mux.h` |
| `ffmpeg_mux_init.c` | `fftools_ffmpeg_mux_init.c` |
| `ffmpeg_opt.c` | `fftools_ffmpeg_opt.c` |
| `ffmpeg_sched.c` | `fftools_ffmpeg_sched.c` |
| `ffmpeg_sched.h` | `fftools_ffmpeg_sched.h` |
| `ffprobe.c` | `fftools_ffprobe.c` |
| `fopen_utf8.h` | `fftools_fopen_utf8.h` |
| `sync_queue.c` | `fftools_sync_queue.c` |
| `sync_queue.h` | `fftools_sync_queue.h` |
| `thread_queue.c` | `fftools_thread_queue.c` |
| `thread_queue.h` | `fftools_thread_queue.h` |
| `opt_common.c` | `fftools_opt_common.c` |
| `opt_common.h` | `fftools_opt_common.h` |

**New files to create:**
- `fftools_ffmpeg_utils.h` (from `ffmpeg_utils.h`)

**Files to remove:**
- `fftools_objpool.c` / `fftools_objpool.h` (no longer exists in 8.1)

### Step 3: Adapt Include References

After copying, update `#include` directives in all fftools_ files:

**Pattern:** Replace direct includes with fftools_ prefixed versions:

```c
// Old (ffmpeg-kit 6.0 style)
#include "cmdutils.h"
#include "ffmpeg.h"
#include "sync_queue.h"

// New (ffmpeg-kit 8.1 style)
#include "fftools_cmdutils.h"
#include "fftools_ffmpeg.h"
#include "fftools_sync_queue.h"
```

**Specific changes needed in each file:**

In `fftools_ffmpeg.h`:
```c
#include "fftools_cmdutils.h"
#include "fftools_ffmpeg_sched.h"
#include "fftools_sync_queue.h"
```

In `fftools_ffmpeg.c`:
```c
#include "fftools_ffmpeg.h"
#include "fftools_ffmpeg_dec.h"  // if needed
// ... etc
```

### Step 4: Port ffmpegkit.c (JNI Layer)

The main JNI bridge file `ffmpegkit.c` needs updates:

1. **Update `#include` paths** to reference new header names
2. **Update function signatures** if any ffmpeg API changed between 6.0 and 8.1
3. **Add new function declarations** for any new fftools functions exposed via JNI

Key areas to check:
- `libavcodec/jni.h` - verify still exists in ffmpeg 8.1
- `libavutil/bprint.h` - verify API compatibility
- `libavutil/file.h` - verify API compatibility
- Session management functions

### Step 5: Update Build Configuration

**`scripts/function-android.sh`:**
- Verify `get_size_optimization_cflags` works with ffmpeg 8.1
- Check if any new compiler flags are needed

**`android/ffmpeg-kit-android-lib/build.gradle`:**
- Update `compileSdk`, `minSdk`, `targetSdk` as needed
- Update `ndkVersion` to match r25b
- Update `versionCode` and `versionName`

**`tools/android/build.gradle`:**
- Same updates as above for the release build variant

### Step 6: Build External Libraries

Since we're doing a full build, the existing build scripts should handle downloading and building all external libraries. The key libraries to verify:

- x264, x265 (GPL)
- dav1d, libaom (AV1)
- opus, lame, twolame (audio)
- freetype, fribidi, harfbuzz (text rendering)
- And all others listed in `scripts/source.sh`

**Command:**
```bash
cd /home/pisces312/ffmpeg-kit-8.1
./android.sh --enable-gpl --disable-arm-v7a --disable-arm-v7a-neon --disable-x86 --disable-x86-64
```

This builds only arm64-v8a with GPL enabled.

### Step 7: Build FFmpeg

The build script will automatically build ffmpeg with the correct configure flags based on enabled libraries.

**Verify ffmpeg 8.1 configure works:**
```bash
cd /home/pisces312/ffmpeg-kit-8.1
# Check that scripts/source.sh points to ffmpeg 8.1
# The build system will download and build ffmpeg from source
```

### Step 8: Build JNI Libraries

After ffmpeg and external libs are built:

1. The build system compiles `ffmpegkit.c`, `ffprobekit.c`, `ffmpegkit_abidetect.c`
2. Links against ffmpeg static libraries
3. Produces `libffmpegkit.so`, `libffmpegkit_abidetect.so`

### Step 9: Package AAR

The build system runs Gradle to produce the AAR:

```bash
cd /home/pisces312/ffmpeg-kit-8.1/android
./gradlew :ffmpeg-kit-android-lib:assembleRelease
```

**Output:** `prebuilt/bundle-android-aar/ffmpeg-kit/ffmpeg-kit.aar`

### Step 10: Verify AAR

Check the AAR contains:
- `jni/arm64-v8a/libavcodec.so`
- `jni/arm64-v8a/libavformat.so`
- `jni/arm64-v8a/libavutil.so`
- `jni/arm64-v8a/libswresample.so`
- `jni/arm64-v8a/libswscale.so`
- `jni/arm64-v8a/libffmpegkit.so`
- `jni/arm64-v8a/libffmpegkit_abidetect.so`
- `classes.jar` (Java API)
- `AndroidManifest.xml`

---

## Risk Areas and Mitigations

### 1. ffmpeg API Changes (6.0 → 8.1)
- **Risk:** Function signatures, struct layouts, or enum values may have changed
- **Mitigation:** Compile and fix errors iteratively. The fftools files are the main integration point.

### 2. New Scheduler Architecture
- **Risk:** ffmpeg 8.1 uses a new scheduler-based threading model (`ffmpeg_sched.c`)
- **Mitigation:** Copy the new files and adapt includes. May need to expose new JNI methods.

### 3. External Library Version Compatibility
- **Risk:** External library versions in `source.sh` may not be compatible with ffmpeg 8.1
- **Mitigation:** Update library versions in `source.sh` if needed. Check ffmpeg 8.1 release notes for minimum versions.

### 4. NDK Compatibility
- **Risk:** NDK r25b may have different behavior than the NDK used for ffmpeg-kit 6.0
- **Mitigation:** The build scripts already handle NDK version detection. Test build early.

---

## Execution Order

1. Update version strings (quick, low risk)
2. Copy fresh fftools source from ffmpeg 8.1
3. Adapt include references in all fftools_ files
4. Port ffmpegkit.c JNI layer
5. Update build configuration files
6. Test build with `--help` to verify script changes
7. Build external libraries
8. Build ffmpeg
9. Build JNI libraries
10. Package and verify AAR

---

## Estimated Time

- Steps 1-5 (code changes): ~1-2 hours
- Steps 6-9 (build): ~2-4 hours (depending on machine speed)
- Step 10 (verification): ~15 minutes

**Total:** ~4-6 hours
