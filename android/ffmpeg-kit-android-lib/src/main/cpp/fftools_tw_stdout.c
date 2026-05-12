/*
 * Copyright (c) The FFmpeg developers
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

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "fftools_avtextwriters.h"
#include "fftools_cmdutils.h"
#include "libavutil/log.h"
#include "libavutil/opt.h"

/* AV_LOG Writer - redirects ffprobe output to av_log so Java layer can capture it */

# define WRITER_NAME "avlogwriter"
# define AVLOG_BUF_SIZE 4096

typedef struct AVLogWriterContext {
    const AVClass *class;
    char buf[AVLOG_BUF_SIZE];
    int  buf_pos;
} AVLogWriterContext;

static const char *avlogwriter_get_name(void *ctx)
{
    return WRITER_NAME;
}

static const AVClass avlogwriter_class = {
    .class_name = WRITER_NAME,
    .item_name = avlogwriter_get_name,
};

static void avlog_flush_buffer(AVLogWriterContext *ctx)
{
    if (ctx->buf_pos > 0) {
        /* Remove trailing newline if present, av_log adds its own */
        while (ctx->buf_pos > 0 && (ctx->buf[ctx->buf_pos - 1] == '\n' || ctx->buf[ctx->buf_pos - 1] == '\r'))
            ctx->buf_pos--;
        ctx->buf[ctx->buf_pos] = '\0';
        if (ctx->buf_pos > 0)
            av_log(NULL, AV_LOG_STDERR, "%s", ctx->buf);
        ctx->buf_pos = 0;
    }
}

static void avlog_w8(AVTextWriterContext *wctx, int b)
{
    AVLogWriterContext *ctx = wctx->priv;
    if (ctx->buf_pos < AVLOG_BUF_SIZE - 1) {
        ctx->buf[ctx->buf_pos++] = (char)b;
        if (b == '\n')
            avlog_flush_buffer(ctx);
    } else {
        avlog_flush_buffer(ctx);
        ctx->buf[ctx->buf_pos++] = (char)b;
        if (b == '\n')
            avlog_flush_buffer(ctx);
    }
}

static void avlog_put_str(AVTextWriterContext *wctx, const char *str)
{
    AVLogWriterContext *ctx = wctx->priv;
    int len = strlen(str);
    int i;

    for (i = 0; i < len; i++) {
        if (ctx->buf_pos < AVLOG_BUF_SIZE - 1) {
            ctx->buf[ctx->buf_pos++] = str[i];
            if (str[i] == '\n')
                avlog_flush_buffer(ctx);
        } else {
            avlog_flush_buffer(ctx);
            ctx->buf[ctx->buf_pos++] = str[i];
            if (str[i] == '\n')
                avlog_flush_buffer(ctx);
        }
    }
}

static void avlog_vprintf(AVTextWriterContext *wctx, const char *fmt, va_list vl)
{
    AVLogWriterContext *ctx = wctx->priv;
    int remaining = AVLOG_BUF_SIZE - ctx->buf_pos - 1;
    int ret;

    if (remaining <= 0) {
        avlog_flush_buffer(ctx);
        remaining = AVLOG_BUF_SIZE - ctx->buf_pos - 1;
    }

    ret = vsnprintf(ctx->buf + ctx->buf_pos, remaining, fmt, vl);
    if (ret > 0) {
        int added = ret < remaining ? ret : remaining - 1;
        ctx->buf_pos += added;
        /* Check for newlines in the added content */
        for (int i = ctx->buf_pos - added; i < ctx->buf_pos; i++) {
            if (ctx->buf[i] == '\n') {
                avlog_flush_buffer(ctx);
                break;
            }
        }
    }
}

static int avlog_uninit(AVTextWriterContext *wctx)
{
    AVLogWriterContext *ctx = wctx->priv;
    avlog_flush_buffer(ctx);
    return 0;
}

static const AVTextWriter avtextwriter_avlog = {
    .name                 = WRITER_NAME,
    .priv_size            = sizeof(AVLogWriterContext),
    .priv_class           = &avlogwriter_class,
    .writer_put_str       = avlog_put_str,
    .writer_vprintf       = avlog_vprintf,
    .writer_w8            = avlog_w8,
    .uninit               = avlog_uninit,
};

int avtextwriter_create_stdout(AVTextWriterContext **pwctx)
{
    int ret;

    ret = avtextwriter_context_open(pwctx, &avtextwriter_avlog);

    return ret;
}
