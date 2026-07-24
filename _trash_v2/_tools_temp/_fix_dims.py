# -*- coding: utf-8 -*-
# 临时脚本：依据 v3_assets.py 的权威尺寸/帧数，回填 Enemies.gd 与 Player.gd 的 fw/fh/fi/fa。
# 规则：怪物 fw/fh=130/250，Boss=260/500；fi=idle 精灵帧数，fa=attack 精灵帧数。
import re, io, os
from v3_assets import RAW, BOSS_CODES

ROOT = r"E:\Godot\Godot_Project\momogametest"
CODE_FRAMES = {c: fr for (c, en, w, h, fr, cat, kind) in RAW}

def _mcode(s):
    return re.search(r'M-\d+', s).group(0)

def fix_enemies():
    p = os.path.join(ROOT, "src/data/Enemies.gd")
    text = io.open(p, encoding='utf-8').read()
    def repl(m):
        head = m.group(1)
        idle_code = _mcode(head)
        atk_code = re.findall(r'M-\d+', head)[1]
        fw, fh = (260, 500) if idle_code in BOSS_CODES else (130, 250)
        fi = CODE_FRAMES[idle_code]; fa = CODE_FRAMES[atk_code]
        return "%s fw=%d, fh=%d, fi=%d, fa=%d" % (head, fw, fh, fi, fa)
    pat_monster = re.compile(r'(idle=[^,]+,\s*attack=[^,]+,)\s*fw=\d+,\s*fh=\d+,\s*fi=\d+,\s*fa=\d+')
    pat_boss = re.compile(r'(sprite_idle=[^,]+,\s*sprite_attack=[^,]+,)\s*fw=\d+,\s*fh=\d+,\s*fi=\d+,\s*fa=\d+')
    new = pat_monster.sub(repl, text)
    new = pat_boss.sub(repl, new)
    new = new.replace(',,', ',')  # 清除上一轮可能残留的双逗号
    io.open(p, 'w', encoding='utf-8').write(new)
    print("Enemies.gd dims fixed")

def fix_player():
    p = os.path.join(ROOT, "src/player/Player.gd")
    text = io.open(p, encoding='utf-8').read()
    def repl(m):
        anim, path, w, h, fr, fps = m.groups()
        code = re.search(r'A-\d+', path).group(0)
        newfr = CODE_FRAMES[code]
        return '"%s": [SPR+"%s", 130, 250, %d, %s]' % (anim, path, newfr, fps)
    pat = re.compile(r'"(\w+)":\s*\[SPR\+"([^"]+)",\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\]')
    new = pat.sub(repl, text)
    io.open(p, 'w', encoding='utf-8').write(new)
    print("Player.gd dims fixed")

if __name__ == '__main__':
    fix_enemies()
    fix_player()
