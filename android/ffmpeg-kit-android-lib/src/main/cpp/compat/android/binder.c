/*
 * Android Binder handler
 *
 * Copyright (c) 2025 Dmitrii Okunev
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */


#if defined(__ANDROID__)

#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
/* ffmpeg-kit 本地补丁：上游 binder.c 未包含此头，靠隐式声明使用
 * android_get_device_api_level()。JNI 层用 -Werror 编译，隐式声明会直接失败，
 * 故显式包含（签名 int(void) 与隐式推断一致，行为不变）。 */
#include <android/api-level.h>

#include "libavutil/log.h"
#include "binder.h"

/*
 * ffmpeg-kit 本地补丁：上游此处有 `#define THREAD_POOL_SIZE 1`，用于
 * ABinderProcess_setThreadPoolMaxThreadCount(1)。该调用在 App 进程内必然
 * 触发 "Binder threadpool cannot be shrunk after starting" 而 SIGABRT，
 * 已整体移除，见下方 android_binder_threadpool_init() 的说明。
 */

static void *dlopen_libbinder_ndk(void)
{
    /*
     * libbinder_ndk.so often does not contain the functions we need, so making
     * this dependency optional, thus using dlopen/dlsym instead of linking.
     *
     * See also: https://source.android.com/docs/core/architecture/aidl/aidl-backends
     */

    void *h = dlopen("libbinder_ndk.so", RTLD_NOW | RTLD_LOCAL);
    if (h != NULL)
        return h;

    av_log(NULL, AV_LOG_WARNING,
           "android/binder: unable to load libbinder_ndk.so: '%s'; skipping binder threadpool init (MediaCodec likely won't work)\n",
           dlerror());
    return NULL;
}

static void android_binder_threadpool_init(void)
{
    typedef void (*start_thread_pool_fn)(void);

    start_thread_pool_fn start_thread_pool = NULL;

    void *h = dlopen_libbinder_ndk();
    if (h == NULL)
        return;

    start_thread_pool =
        (start_thread_pool_fn) dlsym(h, "ABinderProcess_startThreadPool");

    if (start_thread_pool == NULL) {
        av_log(NULL, AV_LOG_WARNING,
               "android/binder: ABinderProcess_startThreadPool not found; skipping threadpool init (MediaCodec likely won't work)\n");
        return;
    }

    /*
     * ffmpeg-kit 本地补丁：绝不调用 ABinderProcess_setThreadPoolMaxThreadCount()。
     *
     * 上游这份代码是给 ffmpeg 独立可执行文件用的（进程内 binder 池尚未启动，
     * 设上限不会触发断言）。但 libffmpegkit.so 嵌入 App 时运行在 Java/ART 进程里，
     * binder 线程池早已由框架启动且上限由框架设定，此时传 1 就构成"缩容"：
     *   ProcessState::setThreadPoolMaxThreadCount()
     *     LOG_ALWAYS_FATAL_IF(mThreadPoolStarted && maxThreads < mMaxThreads,
     *                         "Binder threadpool cannot be shrunk after starting")
     * 直接 SIGABRT（实测 Android 15+ 必崩，崩在 ffmpeg_execute 开头）。
     * startThreadPool() 是幂等的，已启动时直接返回，所以只保留它：
     * 既能保证池存在，又绝不改动上限。
     */
    start_thread_pool();
    av_log(NULL, AV_LOG_DEBUG,
           "android/binder: ABinderProcess_startThreadPool() called\n");
}

void android_binder_threadpool_init_if_required(void)
{
#if __ANDROID_API__ >= 24
    if (android_get_device_api_level() < 35) {
        // the issue with the thread pool was introduced in Android 15 (API 35)
        av_log(NULL, AV_LOG_DEBUG,
               "android/binder: API<35, thus no need to initialize a thread pool\n");
        return;
    }
    android_binder_threadpool_init();
#else
    // android_get_device_api_level was introduced in API 24, so we cannot use it
    // to detect the API level in API<24. For simplicity we just assume
    // libbinder_ndk.so on the system running this code would have API level < 35;
    av_log(NULL, AV_LOG_DEBUG,
           "android/binder: is built with API<24, assuming this is not Android 15+\n");
#endif
}

#endif                          /* __ANDROID__ */
