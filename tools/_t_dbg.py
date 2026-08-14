import sys, traceback
sys.path.insert(0, r"E:/Godot/Godot_Project/momogametest/tools")
print("A: importing sprite_tool")
try:
    import sprite_tool
    print("B: import ok")
except Exception:
    traceback.print_exc()
    sys.exit(1)
print("C: creating app")
from PySide6.QtWidgets import QApplication
app = QApplication([])
print("D: app ok")
try:
    w = sprite_tool.SpriteToolWindow()
    print("E: window ok", w.windowTitle())
except Exception:
    traceback.print_exc()
    sys.exit(1)
