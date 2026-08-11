# PixelClean — AI 用法说明

## 工具用途

将 AI 生成的大尺寸"伪像素画"转为真正的小尺寸游戏像素图。支持图片（PNG）和视频（MP4 等）输入。

## 用法

```
pixanalyze <输入文件> [选项]
```

自动识别图片/视频，图片输出 PNG，视频输出 GIF。

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--algorithm` | cluster | 调色板算法：cluster 或 greedy |
| `--max-colors` | 64 | 调色板最大颜色数 |
| `--threshold` | 15.0 | 颜色合并阈值 ΔE |
| `--size` | 自动检测 | 小图尺寸，格式 WxH |
| `--palette` | 自动提取 | 参考调色板，hex 格式（如 FF000000FF00...） |
| `--expand-threshold` | 20.0 | 调色板扩展阈值 ΔE |
| `--max-expand` | 16 | 最大扩展颜色数 |
| `--no-remove-bg` | 关闭 | 不删除背景 |
| `--sdf` | 关闭 | 输出 SDF 图 |
| `--fps` | 原始帧率 | 拆帧帧率（仅视频） |
| `--dup-threshold` | 0.99 | 帧去重相似度阈值（仅视频） |
| `--keep-frames` | 关闭 | 保留 ffmpeg 拆帧原始文件（仅视频） |
| `-o` | 自动推导 | 输出文件路径 |

## 输出文件

### 图片输入（PNG）

| 条件 | 输出文件 |
|------|----------|
| 始终 | `{name}_small.png` — 像素小图 |
| 去背景开启 | `{name}_alpha.png` — Alpha 遮罩 |
| 去背景开启 | `{name}_edge.png` — 边缘图 |
| 去背景开启且 `--sdf` | `{name}_sdf.png` — SDF 图 |
| 始终 | `{name}_small.json` — 元数据 |

### 视频输入

| 条件 | 输出文件 |
|------|----------|
| 始终 | `{name}.gif` — 像素 GIF 动画 |
| 去背景开启 | `{name}_alpha.gif` — Alpha GIF |
| 去背景开启 | `{name}_edge.gif` — 边缘 GIF |
| 去背景开启且 `--sdf` | `{name}_sdf.gif` — SDF GIF |
| 始终 | `{name}.json` — 元数据 |

## 典型用法

```bash
# 图片：自动提取
pixanalyze character.png --sdf

# 视频：使用已知调色板
pixanalyze attack.mp4 --palette <hex> --max-expand 0

# 指定尺寸
pixanalyze character.png --size 64x64
```

## 依赖工具

- `ffmpeg.exe` — 视频拆帧（仅视频输入时需要）
- `spritefusion-pixel-snapper.exe` — 自动检测像素块尺寸

这些工具需与 pixanalyze.exe 放在同一目录。
