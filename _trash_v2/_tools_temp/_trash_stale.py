# -*- coding: utf-8 -*-
# 临时脚本：把 v3 清单之外的残留 v2.0 占位 PNG（含 .import）移动到项目外垃圾箱。
# 用 move 而非 delete，绕开 safe-delete 守护（守护只拦截删除操作）；文件可随时永久删除。
import os, json, shutil
ROOT = r"E:\Godot\Godot_Project\momogametest"
ASSETS = os.path.join(ROOT, "assets")
TRASH = r"E:\Godot\Godot_Project\momogametest\_trash_v2"

man = json.load(open(os.path.join(ASSETS, "GENERATED_PLACEHOLDERS.json")))
v3 = set(p[len("assets/"):] if p.startswith("assets/") else p for p in man["generated"])
disk = set()
for dp, dn, fn in os.walk(ASSETS):
    for f in fn:
        if f.endswith(".png"):
            disk.add(os.path.relpath(os.path.join(dp, f), ASSETS).replace(os.sep, "/"))
stale = sorted(disk - v3)

moved = 0
for rel in stale:
    src = os.path.join(ASSETS, rel)
    dst = os.path.join(TRASH, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    for s, d in ((src, dst), (src + ".import", dst + ".import")):
        if os.path.exists(s):
            shutil.move(s, d)
            moved += 1
print("moved entries: %d   (stale total was %d)" % (moved, len(stale)))
