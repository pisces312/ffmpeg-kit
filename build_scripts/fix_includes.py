#!/usr/bin/env python3
"""修复include路径"""
import os

cpp_dir = "/home/pisces312/ffmpeg-kit-8.1/android/ffmpeg-kit-android-lib/src/main/cpp"

files = [
    "fftools_textformat.c", "fftools_textformat.h",
    "fftools_tf_compact.c", "fftools_tf_default.c", "fftools_tf_flat.c",
    "fftools_tf_ini.c", "fftools_tf_json.c", "fftools_tf_mermaid.c",
    "fftools_tf_xml.c", "fftools_tw_avio.c", "fftools_tw_buffer.c",
    "fftools_tw_stdout.c", "fftools_graphprint.c", "fftools_graphprint.h",
    "fftools_resman.c", "fftools_resman.h",
    "fftools_tf_internal.h", "fftools_tf_mermaid.h",
]

replacements = [
    ('"avtextformat.h"', '"fftools_textformat.h"'),
    ('"avtextwriters.h"', '"fftools_avtextwriters.h"'),
    ('"tf_internal.h"', '"fftools_tf_internal.h"'),
    ('"tf_mermaid.h"', '"fftools_tf_mermaid.h"'),
    ('"graphprint.h"', '"fftools_graphprint.h"'),
    ('"resman.h"', '"fftools_resman.h"'),
    ('"fftools/ffmpeg.h"', '"fftools_ffmpeg.h"'),
    ('"fftools/ffmpeg_mux.h"', '"fftools_ffmpeg_mux.h"'),
    ('"fftools/textformat/avtextformat.h"', '"fftools_textformat.h"'),
]

for fname in files:
    fpath = os.path.join(cpp_dir, fname)
    if not os.path.exists(fpath):
        print(f"SKIP: {fname}")
        continue
    with open(fpath, "r") as f:
        content = f.read()
    changed = False
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            changed = True
    if changed:
        with open(fpath, "w") as f:
            f.write(content)
        print(f"Fixed: {fname}")

print("Done")
