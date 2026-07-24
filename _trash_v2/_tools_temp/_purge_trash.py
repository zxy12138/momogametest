# -*- coding: utf-8 -*-
# 临时脚本：永久删除 _trash_v2/ 内的残留（按切片，单批控制在安全守护阈值内）。
import os, sys
TRASH = r"E:\Godot\Godot_Project\momogametest\_trash_v2"
files = []
for dp, dn, fn in os.walk(TRASH):
    for f in fn:
        files.append(os.path.join(dp, f))
files.sort()
start = int(sys.argv[1]) if len(sys.argv) > 1 else 0
end = int(sys.argv[2]) if len(sys.argv) > 2 else len(files)
batch = files[start:end]
print("trash total=%d  本批 %d (idx %d..%d)" % (len(files), len(batch), start, end))
ok = 0
for fp in batch:
    try:
        os.remove(fp)
        ok += 1
    except OSError as e:
        print("  (skip %s: %s)" % (fp, e))
print("  实际删除: %d" % ok)
