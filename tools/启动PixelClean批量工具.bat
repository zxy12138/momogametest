@echo off
chcp 65001 >nul
cd /d "%~dp0"
start "" "E:\python project\开发Python插件管理分发系统\.venv\Scripts\pythonw.exe" "%~dp0pixelclean_batch_gui.py"
