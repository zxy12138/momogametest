# CLAUDE.md

## 项目概述

PixelClean 是将 AI 生成的"伪像素画"转为真正小尺寸游戏像素图的 CLI 工具。基于 .NET 10.0，使用 SixLabors.ImageSharp 处理图像。

## 构建

```bash
dotnet build src/PixelClean
```

## 发布（NativeAOT）

需要 Visual Studio C++ 工具链（link.exe）。

```bash
dotnet publish src/PixelClean -c Release -r win-x64 -o publish -p:PublishAot=true
```

## 项目结构

- `src/PixelClean/Program.cs` — 主程序（调色板提取、降采样、去背景、辅助图）
- `src/PixelClean/DetectionSnapper.cs` — 尺寸探测（调用外部 snapper 工具）
- `publish/` — 发布产物目录
- `images/` — README 示例图片

## 外部依赖

- `ffmpeg.exe` — 视频拆帧
- `spritefusion-pixel-snapper.exe` — 像素块尺寸探测

这两个工具需与 pixanalyze.exe 在同一目录，或放在 `tool/` 子目录下。

## 命名空间

项目命名空间为 `PixelAnalyzer`（历史原因），项目/程序集名已改为 `PixelClean`。

## 编码规则

- 未经用户明确要求，禁止主动修改代码
- 修改超过一个函数，先出方案询问用户
