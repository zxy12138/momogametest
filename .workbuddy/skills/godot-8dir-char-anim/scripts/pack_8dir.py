#!/usr/bin/env python3
"""Pack per-direction frame strips into an 8-direction atlas sheet.

Input layout:
    <input_dir>/<action>/<dir>.png
where <dir>.png is a HORIZONTAL strip of F frames, each CELL_W x CELL_H,
in the order the frames should play (left -> right).

Output:
    <output_dir>/<prefix><action>.png
an atlas with 8 rows (DIR_ORDER) x F columns, cell CELL_W x CELL_H.

Row order (DIR_ORDER index 0..7) matches the Godot resolver in references/convention.md:
    down, down_right, right, up_right, up, up_left, left, down_left

Usage:
    python pack_8dir.py <input_dir> <output_dir> <cell_w> <cell_h> [prefix]

Example:
    python pack_8dir.py ./gen/player ./assets/sprites/player 130 250 A-001_miai_
"""
import os
import sys
from PIL import Image

DIR_ORDER = ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]


def pack_action(action_dir: str, out_path: str, cell_w: int, cell_h: int) -> None:
    strips = {}
    frames = None
    for d in DIR_ORDER:
        p = os.path.join(action_dir, d + ".png")
        if not os.path.exists(p):
            print(f"  WARN missing {d}.png -> blank row")
            strips[d] = None
            continue
        im = Image.open(p).convert("RGBA")
        fw = im.size[0]
        f = fw // cell_w
        if frames is None:
            frames = f
        strips[d] = im

    if not frames or frames == 0:
        print(f"  skip {action_dir}: no valid frames found")
        return

    canvas = Image.new("RGBA", (frames * cell_w, 8 * cell_h), (0, 0, 0, 0))
    for ri, d in enumerate(DIR_ORDER):
        im = strips.get(d)
        if im is None:
            continue
        for ci in range(frames):
            x0 = ci * cell_w
            y0 = ri * cell_h
            frame = im.crop((x0, 0, x0 + cell_w, cell_h))
            canvas.paste(frame, (x0, y0))
    canvas.save(out_path)
    print(f"  wrote {out_path}  ({frames} frames x 8 dirs, cell {cell_w}x{cell_h})")


def main() -> None:
    if len(sys.argv) < 5:
        print("usage: pack_8dir.py <input_dir> <output_dir> <cell_w> <cell_h> [prefix]")
        sys.exit(1)
    input_dir = sys.argv[1]
    output_dir = sys.argv[2]
    cell_w = int(sys.argv[3])
    cell_h = int(sys.argv[4])
    prefix = sys.argv[5] if len(sys.argv) > 5 else "A-001_miai_"
    os.makedirs(output_dir, exist_ok=True)
    for action in sorted(os.listdir(input_dir)):
        ad = os.path.join(input_dir, action)
        if not os.path.isdir(ad):
            continue
        out = os.path.join(output_dir, f"{prefix}{action}.png")
        print(f"packing action '{action}'")
        pack_action(ad, out, cell_w, cell_h)
    print("done.")


if __name__ == "__main__":
    main()
