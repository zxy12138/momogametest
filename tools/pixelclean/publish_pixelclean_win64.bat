@echo off
cd /d %~dp0

echo === 清理 publish 目录（保留 ffmpeg.exe 和 snapper） ===
del /Q publish\pixanalyze.* 2>nul
del /Q publish\SixLabors.* 2>nul
del /Q publish\*.deps.json 2>nul
del /Q publish\*.pdb 2>nul
del /Q publish\*.runtimeconfig.json 2>nul

echo === dotnet publish ===
dotnet publish src\PixelClean -o publish

if %ERRORLEVEL% neq 0 (
    echo Publish failed!
    pause
    exit /b 1
)

echo === Done ===
