#!/usr/bin/env python3
"""把上游 FFmpeg 的 fftools/ 移植到 android/ffmpeg-kit-android-lib/src/main/cpp/

做的三件事：
  1. flatten —— 去掉子目录（graph/ textformat/ resources/），文件名统一加 `fftools_` 前缀
  2. include 改写 —— fftools 内部互相引用的 15 个头文件加前缀
  3. 三方合并 —— 以「本地改动」为 ours、旧版上游为 base、新版上游为 theirs，
     自动把本地改造叠加到新版本上，冲突处留 diff3 标记供人工处理

用法：
  ./port_fftools.py --new /mnt/d/3rd-party-projects/ffmpeg-8.1.3/fftools \\
                    --base /mnt/d/3rd-party-projects/ffmpeg-<旧版>/fftools \\
                    [--cpp <目标目录>] [--apply]

  不加 --apply：只输出差异报告（默认，安全）
  加   --apply：真正的写盘（base==local 的直接覆盖，其余三方合并）

行尾：统一写 LF（仓库内本就是 LF；工作树里部分文件是 CRLF，git 视作相同内容）
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

# 需要加 fftools_ 前缀的头文件（fftools 内部互相引用）
RENAME_HEADERS = [
    "avtextwriters.h", "cmdutils.h", "ffmpeg.h", "ffmpeg_mux.h", "ffmpeg_sched.h",
    "ffmpeg_utils.h", "fopen_utf8.h", "graphprint.h", "opt_common.h", "resman.h",
    "sync_queue.h", "textformat.h", "tf_internal.h", "tf_mermaid.h", "thread_queue.h",
]

# flatten 时的特殊改名：上游 basename -> 本地 basename
SPECIAL = {
    "avtextformat.c": "textformat.c",
    "avtextformat.h": "textformat.h",
}

# 不移植的文件（ffplay 相关，本项目 --disable-programs，只要 ffmpeg/ffprobe）
SKIP_PREFIX = ("ffplay",)

INCLUDE_RE = re.compile(r'#include\s+"([A-Za-z0-9_./]+\.h)"')


def target_name(relpath: str) -> str:
    base = os.path.basename(relpath)
    base = SPECIAL.get(base, base)
    return "fftools_" + base


def rewrite_includes(text: str) -> str:
    def repl(m):
        inc = m.group(1)
        if os.path.basename(inc) in RENAME_HEADERS and "/" not in inc:
            return '#include "fftools_%s"' % inc
        # 带目录的相对引用（如 "textformat/avtextformat.h"）也在 flatten 后失效
        b = os.path.basename(inc)
        if b in RENAME_HEADERS or b in SPECIAL:
            b = SPECIAL.get(b, b)
            return '#include "fftools_%s"' % b
        return m.group(0)

    return INCLUDE_RE.sub(repl, text)


def collect(root: str) -> dict:
    """root/fftools 下所有 .c/.h -> {relpath: abspath}"""
    out = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if not fn.endswith((".c", ".h")):
                continue
            if fn.startswith(SKIP_PREFIX):
                continue
            ap = os.path.join(dirpath, fn)
            rel = os.path.relpath(ap, root)
            out[rel] = ap
    return out


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="surrogateescape", newline="") as f:
        return f.read().replace("\r\n", "\n")


def count_changed_lines(a: str, b: str) -> int:
    if a == b:
        return 0
    n = 0
    for line in _unified(a, b):
        if line[:1] in "+-" and not line.startswith(("+++", "---")):
            n += 1
    return n


def _unified(a: str, b: str):
    import difflib
    return list(difflib.unified_diff(a.splitlines(True), b.splitlines(True), "base", "new", n=0))


def merge3(ours: str, base: str, theirs: str):
    """返回 (merged_text, conflicts)。用 git merge-file 保证 diff3 语义。"""
    with tempfile.TemporaryDirectory() as td:
        po = os.path.join(td, "ours")
        pb = os.path.join(td, "base")
        pt = os.path.join(td, "theirs")
        for p, t in ((po, ours), (pb, base), (pt, theirs)):
            with open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
                f.write(t)
        r = subprocess.run(["git", "merge-file", "-p", "--diff3", po, pb, pt],
                           capture_output=True, text=True)
        # 0 = 干净合并；1..127 = 冲突数；负数 = 出错
        return r.stdout, max(r.returncode, 0)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_cpp = os.path.join(os.path.dirname(here),
                               "android", "ffmpeg-kit-android-lib", "src", "main", "cpp")
    ap = argparse.ArgumentParser()
    ap.add_argument("--new", required=True, help="新版上游 fftools 目录")
    ap.add_argument("--base", help="旧版上游 fftools 目录（三方合并的 base；不填则不能 --apply）")
    ap.add_argument("--cpp", default=default_cpp, help="目标目录（默认仓库内 cpp/）")
    ap.add_argument("--apply", action="store_true", help="真正写盘")
    args = ap.parse_args()

    new_map = collect(args.new)
    base_map = collect(args.base) if args.base else {}

    rows = []          # (status, target, base_delta, new_delta, conflicts)
    touched_new = {}

    for rel, apath in sorted(new_map.items()):
        tgt = target_name(rel)
        local_path = os.path.join(args.cpp, tgt)
        their_txt = rewrite_includes(read_text(apath))

        base_txt = ""
        if rel in base_map:
            base_txt = rewrite_includes(read_text(base_map[rel]))

        if not os.path.exists(local_path):
            rows.append(("NEW", tgt, "-", count_changed_lines(base_txt, their_txt), 0))
            touched_new[tgt] = their_txt
            continue

        our_txt = read_text(local_path)
        if our_txt == their_txt:
            rows.append(("same", tgt, "-", 0, 0))
            continue

        if base_txt and our_txt == base_txt:
            # 本地没有改动，直接跟随上游
            rows.append(("upstream-only", tgt, 0, count_changed_lines(base_txt, their_txt), 0))
            touched_new[tgt] = their_txt
            continue

        if not base_txt:
            rows.append(("NO-BASE", tgt, "?", "?", 0))
            continue

        merged, conflicts = merge3(our_txt, base_txt, their_txt)
        rows.append(("merged", tgt,
                     count_changed_lines(base_txt, our_txt),
                     count_changed_lines(base_txt, their_txt),
                     conflicts))
        touched_new[tgt] = merged

    # 上游已删除、本地还留着的文件
    upstream_targets = {target_name(r) for r in new_map}
    orphans = []
    for fn in sorted(os.listdir(args.cpp)):
        if fn.startswith("fftools_") and fn not in upstream_targets:
            orphans.append(fn)

    w = max(len(r[1]) for r in rows) if rows else 10
    print("%-14s %-*s %8s %8s %6s" % ("STATUS", w, "TARGET", "本地改动", "上游改动", "冲突"))
    print("-" * (16 + w + 26))
    for st, tgt, bd, nd, cf in rows:
        if st == "same":
            continue
        print("%-14s %-*s %8s %8s %6s" % (st, w, tgt, bd, nd, cf))

    changed = [r for r in rows if r[0] != "same"]
    print()
    print("合计：%d 个文件，需处理 %d 个" % (len(rows), len(changed)))
    if orphans:
        print("上游已删除、本地仍存在（需人工确认）：%s" % ", ".join(orphans))
    total_conf = sum(r[4] for r in rows)
    if total_conf:
        print("⚠ 三方合并冲突块合计 %d 处，需人工处理（文件内已标 <<<<<<<）" % total_conf)

    if not args.apply:
        print("\n（未加 --apply，未写盘）")
        return 0

    if not args.base:
        print("ERROR: --apply 必须同时提供 --base", file=sys.stderr)
        return 2

    for tgt, txt in touched_new.items():
        with open(os.path.join(args.cpp, tgt), "w", encoding="utf-8",
                  errors="surrogateescape", newline="\n") as f:
            f.write(txt)
    print("\n已写入 %d 个文件 → %s" % (len(touched_new), args.cpp))
    return 0


if __name__ == "__main__":
    sys.exit(main())
