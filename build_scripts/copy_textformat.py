#!/usr/bin/env python3
"""复制FFmpeg 8.1 fftools textformat/graph源文件"""
import shutil
import os

src = "/home/pisces312/ffmpeg-8.1/fftools"
dst = "/home/pisces312/ffmpeg-kit-8.1/android/ffmpeg-kit-android-lib/src/main/cpp"

files = [
    ("textformat/avtextformat.c", "fftools_textformat.c"),
    ("textformat/avtextformat.h", "fftools_textformat.h"),
    ("textformat/avtextwriters.h", "fftools_avtextwriters.h"),
    ("textformat/tf_compact.c", "fftools_tf_compact.c"),
    ("textformat/tf_default.c", "fftools_tf_default.c"),
    ("textformat/tf_flat.c", "fftools_tf_flat.c"),
    ("textformat/tf_ini.c", "fftools_tf_ini.c"),
    ("textformat/tf_json.c", "fftools_tf_json.c"),
    ("textformat/tf_mermaid.c", "fftools_tf_mermaid.c"),
    ("textformat/tf_mermaid.h", "fftools_tf_mermaid.h"),
    ("textformat/tf_internal.h", "fftools_tf_internal.h"),
    ("textformat/tf_xml.c", "fftools_tf_xml.c"),
    ("textformat/tw_avio.c", "fftools_tw_avio.c"),
    ("textformat/tw_buffer.c", "fftools_tw_buffer.c"),
    ("textformat/tw_stdout.c", "fftools_tw_stdout.c"),
    ("graph/graphprint.c", "fftools_graphprint.c"),
    ("graph/graphprint.h", "fftools_graphprint.h"),
    ("resources/resman.c", "fftools_resman.c"),
    ("resources/resman.h", "fftools_resman.h"),
    ("resources/graph.css.c", "fftools_graph_css.c"),
    ("resources/graph.html.c", "fftools_graph_html.c"),
]

for src_name, dst_name in files:
    src_path = os.path.join(src, src_name)
    dst_path = os.path.join(dst, dst_name)
    shutil.copy2(src_path, dst_path)
    print(f"Copied: {dst_name}")

print("All files copied")
