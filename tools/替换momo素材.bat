@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
echo ============================================
echo  替换 momo_packed 素材（请先完全关闭 Godot！）
echo ============================================
if not exist "assets\sprites\player\momo_packed_new" (
    echo [错误] 找不到新素材目录，请确认 tools/替换momo素材.bat 与项目结构完整。
    pause
    exit /b 1
)
xcopy /Y /E "assets\sprites\player\momo_packed_new\*.*" "assets\sprites\player\momo_packed\" >nul 2>&1
if errorlevel 1 (
    echo [错误] 替换失败。请确认已关闭所有 Godot 窗口/进程后重试。
    pause
    exit /b 1
)
echo [完成] 素材已替换到 momo_packed\
echo 下一步：删除项目根目录 .godot 文件夹，然后重新打开 Godot。
echo （可选）清理临时目录：rmdir /S /Q "assets\sprites\player\momo_packed_new"
pause
