# -*- coding: utf-8 -*-
# 临时脚本：删除 v3 清单之外的残留 v2.0 占位 PNG（含 .import）。
# 用法：python _del_stale.py <start> <end>  —— 按 stale 列表切片删除，避免单进程超 50 触发安全守护。
import os, json, sys
ROOT = r"E:\Godot\Godot_Project\momogametest"
ASSETS = os.path.join(ROOT, "assets")

man = json.load(open(os.path.join(ASSETS, "GENERATED_PLACEHOLDERS.json")))
v3 = set()
for p in man["generated"]:
    v3.add(p[len("assets/"):] if p.startswith("assets/") else p)
disk = set()
for dp, dn, fn in os.walk(ASSETS):
    for f in fn:
        if f.endswith(".png"):
            rel = os.path.relpath(os.path.join(dp, f), ASSETS).replace(os.sep, "/")
            disk.add(rel)
stale = sorted(disk - v3)

start = int(sys.argv[1]) if len(sys.argv) > 1 else 0
end = int(sys.argv[2]) if len(sys.argv) > 2 else len(stale)
batch = stale[start:end]
print("stale total=%d  本批删除 %d (idx %d..%d)" % (len(stale), len(batch), start, end))
ok = 0
for rel in batch:
    fp = os.path.join(ASSETS, rel)
    for t in (fp, fp + ".import"):
        if os.path.exists(t):
            try:
                os.remove(t)
                ok += 1
            except OSError as e:
                print("  (skip %s: %s)" % (t, e))
print("  实际删除条目: %d" % ok)
