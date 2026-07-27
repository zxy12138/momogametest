import sys
sys.path.append(r'C:\Users\dapeng\AppData\Roaming\Python\Python313\site-packages')
from PIL import Image
im = Image.open(r'E:\Godot\Godot_Project\momogametest\Artssucai\momo_jk.PNG')
print('orig size=', im.size, 'mode=', im.mode)
# Resize to a smaller version, keep aspect ratio, max 1024 height
w, h = im.size
scale = 1024.0 / max(w, h)
new_size = (int(w * scale), int(h * scale))
im_small = im.resize(new_size, Image.LANCZOS)
# Save as PNG with no alpha loss (already RGBA)
im_small.save(r'E:\Godot\Godot_Project\momogametest\Artssucai\momo_jk_small.png', optimize=True)
print('saved small:', im_small.size)

# Also save a tiny preview for fast inspection
preview = im.resize((256, int(256 * h / w)), Image.LANCZOS)
preview.save(r'E:\Godot\Godot_Project\momogametest\Artssucai\momo_jk_preview.png', optimize=True)
print('saved preview:', preview.size)
