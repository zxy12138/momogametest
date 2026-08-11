using System.Diagnostics;
using System.Text.Json.Nodes;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Formats.Png;
using SixLabors.ImageSharp.Formats.Gif;
using SixLabors.ImageSharp.Processing;

namespace PixelAnalyzer;

static partial class Program
{
    static readonly HashSet<string> VideoExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp4", ".avi", ".mov", ".mkv", ".webm", ".flv", ".wmv", ".m4v", ".mpg", ".mpeg", ".ts"
    };

    static int Main(string[] args)
    {
        if (args.Length == 0 || args[0] is "--help" or "-h")
        {
            PrintUsage();
            return 0;
        }

        try
        {
            return Run(args);
        }
        catch (CliException ex)
        {
            Console.Error.WriteLine($"错误: {ex.Message}");
            return 1;
        }
    }

    static bool IsVideoFile(string path) =>
        VideoExtensions.Contains(Path.GetExtension(path));

    static void PrintUsage()
    {
        Console.WriteLine("""
            PixelClean - 将 AI 像素画转为小尺寸游戏像素图

            用法:
              pixanalyze <input> [选项]

            自动识别图片（PNG）和视频（MP4 等），图片输出 PNG，视频输出 GIF。

            参数:
              --algorithm <cluster|greedy>  调色板算法（默认 cluster）
              --max-colors <N>              调色板最大颜色数（默认 64）
              --threshold <N>               颜色合并阈值 ΔE（默认 15.0）
              --size <WxH>                  小图尺寸（可选，不指定则自动检测）
              --palette <hex>               参考调色板（可选，不传则自动提取）
              --expand-threshold <N>        调色板扩展阈值 ΔE（默认 20.0）
              --max-expand <N>              最大扩展颜色数（默认 16）
              --no-remove-bg                不删除背景（默认自动删除）
              --sdf                         输出 SDF 图（默认关闭）
              --fps <N>                     拆帧帧率（默认视频原始帧率，仅视频）
              --dup-threshold <N>           帧去重相似度阈值（默认 0.99，仅视频）
              --keep-frames                 保留 ffmpeg 拆帧原始文件（仅视频）
              -o <file>                     输出文件路径（可选，默认从输入名推导）
            """);
    }

    #region Main Logic

    static int Run(string[] args)
    {
        var inputPath = GetPositionalArg(args) ?? throw new CliException("缺少输入文件路径");
        var output = ParseOptional(args, "-o");
        var algo = ParseOptional(args, "--algorithm") ?? "cluster";
        var maxColors = ParseInt(args, "--max-colors", 64);
        var threshold = ParseDouble(args, "--threshold", 15.0);
        var sizeStr = ParseOptional(args, "--size");
        var paletteHex = ParseOptional(args, "--palette");
        var expandThreshold = ParseDouble(args, "--expand-threshold", 20.0);
        var maxExpand = ParseInt(args, "--max-expand", 16);
        var removeBg = !HasFlag(args, "--no-remove-bg");
        var sdf = HasFlag(args, "--sdf");
        var fpsVal = ParseNullableInt(args, "--fps");
        var keepFrames = HasFlag(args, "--keep-frames");
        var dupThreshold = ParseDouble(args, "--dup-threshold", 0.99);

        if (!File.Exists(inputPath))
            throw new CliException($"文件不存在: {inputPath}");

        bool isVideo = IsVideoFile(inputPath);

        // 推导输出路径
        if (output == null)
        {
            string dir = Path.GetDirectoryName(inputPath) ?? "";
            string name = Path.GetFileNameWithoutExtension(inputPath);
            string ext = isVideo ? ".gif" : "_small.png";
            output = Path.Combine(dir, name + ext);
        }
        else if (isVideo && !output.EndsWith(".gif", StringComparison.OrdinalIgnoreCase))
        {
            output += ".gif";
        }

        // 解析目标尺寸
        int targetW = 0, targetH = 0;
        if (sizeStr != null)
        {
            var sizeParts = sizeStr.Split('x', 'X', '*', '×');
            if (sizeParts.Length != 2 || !int.TryParse(sizeParts[0], out targetW) || !int.TryParse(sizeParts[1], out targetH))
                throw new CliException($"无效的尺寸格式: {sizeStr}，应为 WxH（如 178x100）");
        }

        if (isVideo)
            return ExtractVideo(inputPath, output, algo, maxColors, threshold, paletteHex,
                expandThreshold, maxExpand, removeBg, fpsVal, keepFrames,
                dupThreshold, targetW, targetH, sdf);
        else
            return ExtractImage(inputPath, output, algo, maxColors, threshold, paletteHex,
                removeBg, targetW, targetH, sdf);
    }

    static int ExtractImage(string imagePath, string output, string algo, int maxColors, double threshold,
        string? paletteHex, bool removeBg,
        int targetW, int targetH, bool sdf)
    {
        using var image = Image.Load<Rgba32>(imagePath);
        Console.WriteLine($"原始尺寸: {image.Width}x{image.Height}");

        bool hasAlpha = DetectAlpha(image);

        // 调色板
        List<Rgba32> palette;
        int uniqueColors;
        if (paletteHex != null)
        {
            palette = ParsePaletteFromHex(paletteHex);
            uniqueColors = palette.Count;
            Console.WriteLine($"使用传入调色板: {palette.Count} 色");
        }
        else
        {
            Console.WriteLine($"提取调色板 (算法={algo}, 最大={maxColors})...");
            palette = ExtractMinimalPalette(image, algo, maxColors, threshold, hasAlpha, removeBg, out uniqueColors);
            Console.WriteLine($"最小调色板: {palette.Count} 色 (含透明={hasAlpha})");
        }

        Console.WriteLine("清理图像...");
        using var cleaned = RemapImage(image, palette);

        // 小图尺寸（在删背景前探测）
        if (targetW == 0 || targetH == 0)
        {
            Console.WriteLine("尺寸探测（snapper）...");
            (targetW, targetH) = DetectSmallSize(cleaned);
        }
        Console.WriteLine($"小图尺寸: {targetW}x{targetH}");

        double scaleX = (double)image.Width / targetW;
        double scaleY = (double)image.Height / targetH;

        // 在大图上删背景 + 生成 alpha mask
        Image<Rgba32>? alphaMaskLarge = null;
        if (removeBg)
        {
            Console.WriteLine("删除背景...");
            alphaMaskLarge = RemoveBgCreateMask(cleaned, palette, threshold);
        }

        // 降采样（transparent 通过投票自然处理）
        Console.WriteLine("降采样...");
        using var small = DownscaleVote(cleaned, (int)Math.Round(scaleX), (int)Math.Round(scaleY), palette);

        // 保存普通 PNG
        small.Save(output, new PngEncoder());
        Console.WriteLine($"已保存: {output} ({targetW}x{targetH}, {palette.Count} 色)");

        // 辅助图（alpha/edge/sdf）
        string dir = Path.GetDirectoryName(output) ?? "";
        string name = Path.GetFileNameWithoutExtension(output);
        bool needMask = removeBg || hasAlpha;

        if (needMask && alphaMaskLarge != null)
        {
            // Alpha 图：线性缩小
            using (alphaMaskLarge)
            {
                using var alphaSmall = LinearDownscale(alphaMaskLarge, targetW, targetH);
                var alphaPath = Path.Combine(dir, name + "_alpha.png");
                alphaSmall.Save(alphaPath, new PngEncoder());
                Console.WriteLine($"已保存: {alphaPath} - Alpha 遮罩");

                // Edge 图：腐蚀 → XOR → 线性缩小
                int bw = (int)Math.Round((scaleX + scaleY) / 2);
                using var edgeMask = CreateEdgeMask(alphaMaskLarge, bw);
                using var edgeSmall = LinearDownscale(edgeMask, targetW, targetH);
                var edgePath = Path.Combine(dir, name + "_edge.png");
                edgeSmall.Save(edgePath, new PngEncoder());
                Console.WriteLine($"已保存: {edgePath} - 边缘图");

                // SDF 图（可选）
                if (sdf)
                {
                    using var sdfImg = ComputeSdf(alphaMaskLarge, targetW, targetH, bw);
                    var sdfPath = Path.Combine(dir, name + "_sdf.png");
                    sdfImg.Save(sdfPath, new PngEncoder());
                    Console.WriteLine($"已保存: {sdfPath} - SDF 图");
                }
            }
        }

        // 保存 JSON
        SaveJson(output, imagePath, (image.Width, image.Height), targetW, targetH,
            uniqueColors, palette.Count, hasAlpha || removeBg, palette);

        return 0;
    }

    static int ExtractVideo(string videoPath, string output, string algo, int maxColors, double threshold,
        string? paletteHex, double expandThreshold, int maxExpand, bool removeBg,
        int? fpsVal, bool keepFrames, double dupThreshold,
        int targetW, int targetH, bool sdf)
    {
        // ffmpeg 拆帧
        var ffmpegPath = FindTool("ffmpeg.exe");

        foreach (var oldDir in Directory.GetDirectories(Path.GetTempPath(), "pixanalyze_*"))
        {
            try { Directory.Delete(oldDir, true); } catch { }
        }

        var tempDir = Path.Combine(Path.GetTempPath(), $"pixanalyze_{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        Console.WriteLine($"拆帧到临时目录: {tempDir}");

        RunFfmpegExtract(ffmpegPath, videoPath, tempDir, fpsVal);

        var frameFiles = Directory.GetFiles(tempDir, "*.png").OrderBy(f => f).ToArray();
        if (frameFiles.Length == 0)
            throw new CliException("ffmpeg 未生成任何帧文件");

        Console.WriteLine($"共 {frameFiles.Length} 帧");

        using var firstFrame = Image.Load<Rgba32>(frameFiles[0]);

        // 调色板
        List<Rgba32> palette;
        if (paletteHex != null)
        {
            palette = ParsePaletteFromHex(paletteHex);
            Console.WriteLine($"使用传入调色板: {palette.Count} 色");
        }
        else
        {
            Console.WriteLine("自动提取调色板...");
            bool hasAlpha = DetectAlpha(firstFrame);
            int _;
            palette = ExtractMinimalPalette(firstFrame, "cluster", maxColors, threshold, hasAlpha, removeBg, out _);
            Console.WriteLine($"自动提取调色板: {palette.Count} 色");
        }

        // 小图尺寸
        double scaleX, scaleY;
        if (targetW == 0 || targetH == 0)
        {
            using var remappedFirst = RemapImage(firstFrame, palette);
            Console.WriteLine("snapper 自动检测小图尺寸...");
            (targetW, targetH) = DetectSmallSize(remappedFirst);
            scaleX = (double)firstFrame.Width / targetW;
            scaleY = (double)firstFrame.Height / targetH;
            Console.WriteLine($"  小图尺寸: {targetW}x{targetH}, 缩放: {scaleX:F2}x{scaleY:F2}");
        }
        else
        {
            scaleX = (double)firstFrame.Width / targetW;
            scaleY = (double)firstFrame.Height / targetH;
        }
        Console.WriteLine($"帧尺寸: {firstFrame.Width}x{firstFrame.Height}, 缩放: {scaleX:F2}x{scaleY:F2}, 目标: {targetW}x{targetH}");

        // 加载所有帧
        Console.WriteLine("加载所有帧...");
        var frames = new Image<Rgba32>[frameFiles.Length];
        for (int i = 0; i < frameFiles.Length; i++)
            frames[i] = Image.Load<Rgba32>(frameFiles[i]);

        // 增量调色板扩展
        if (paletteHex != null && maxExpand > 0)
        {
            Console.WriteLine("增量调色板扩展...");
            var paletteLabList = new List<(double L, double a, double b)>();
            for (int i = 0; i < palette.Count; i++)
            {
                var c = palette[i];
                paletteLabList.Add(c.A == 0 ? (0, 0, 0) : RgbToLab(c.R, c.G, c.B));
            }

            int totalAdded = 0;
            for (int fi = 0; fi < frames.Length && totalAdded < maxExpand; fi++)
            {
                var frame = frames[fi];
                int fw = frame.Width, fh = frame.Height;

                var frameColors = new HashSet<int>();
                for (int y = 0; y < fh; y++)
                {
                    for (int x = 0; x < fw; x++)
                    {
                        var p = frame[x, y];
                        if (p.A < 128) continue;
                        int key = ((p.R & 0xF8) << 10) | ((p.G & 0xFC) << 3) | (p.B >> 3);
                        frameColors.Add(key);
                    }
                }

                var newCandidates = new List<(double L, double a, double b, byte r, byte g, byte bv)>();
                foreach (int v in frameColors)
                {
                    byte cr = (byte)((v >> 10) & 0xF8);
                    byte cg = (byte)((v >> 3) & 0xFC);
                    byte cb = (byte)((v << 3) & 0xF8);
                    var lab = RgbToLab(cr, cg, cb);

                    double minDist = double.MaxValue;
                    for (int i = 0; i < paletteLabList.Count; i++)
                    {
                        if (palette[i].A == 0) continue;
                        double d = LabDistance(lab, paletteLabList[i]);
                        if (d < minDist) minDist = d;
                    }

                    if (minDist > expandThreshold)
                        newCandidates.Add((lab.L, lab.a, lab.b, cr, cg, cb));
                }

                int paletteStartCount = palette.Count;
                foreach (var cand in newCandidates)
                {
                    if (totalAdded >= maxExpand) break;

                    bool tooClose = false;
                    for (int i = paletteStartCount; i < palette.Count; i++)
                    {
                        if (LabDistance((cand.L, cand.a, cand.b), paletteLabList[i]) < expandThreshold)
                        {
                            tooClose = true;
                            break;
                        }
                    }
                    if (tooClose) continue;

                    paletteLabList.Add((cand.L, cand.a, cand.b));
                    palette.Add(new Rgba32(cand.r, cand.g, cand.bv, 255));
                    totalAdded++;
                }

                if ((fi + 1) % 20 == 0 || fi == frames.Length - 1)
                    Console.WriteLine($"  帧 {fi + 1}/{frames.Length}, 调色板 {palette.Count} 色 (+{totalAdded})");
            }

            if (totalAdded > 0)
                Console.WriteLine($"调色板扩展完成: +{totalAdded} 色 → {palette.Count} 色");
            else
                Console.WriteLine("调色板无需扩展");
        }

        // 并发帧处理
        Console.WriteLine("并发帧处理...");
        var smallFrames = new Image<Rgba32>[frames.Length];
        bool needMask = removeBg; // 视频帧通常无 alpha，仅 removeBg 时输出辅助图
        var smallFramesAlpha = needMask ? new Image<Rgba32>[frames.Length] : null;
        var smallFramesEdge = needMask ? new Image<Rgba32>[frames.Length] : null;
        var smallFramesSdf = (needMask && sdf) ? new Image<Rgba32>[frames.Length] : null;
        int processed = 0;

        var paletteLabs = new (double L, double a, double b)?[palette.Count];
        for (int i = 0; i < palette.Count; i++)
        {
            var c = palette[i];
            paletteLabs[i] = c.A == 0 ? null : RgbToLab(c.R, c.G, c.B);
        }

        int bw = (int)Math.Round((scaleX + scaleY) / 2);

        Parallel.For(0, frames.Length, fi =>
        {
            using var remapped = RemapImageWithLabs(frames[fi], palette, paletteLabs);

            // 在大图上删背景 + 生成 alpha mask
            Image<Rgba32>? alphaMask = null;
            if (removeBg)
                alphaMask = RemoveBgCreateMask(remapped, palette, threshold);

            // 降采样（transparent 通过投票自然处理）
            var small = DownscaleVote(remapped, (int)Math.Round(scaleX), (int)Math.Round(scaleY), palette);
            smallFrames[fi] = small;

            // 辅助图
            if (needMask && alphaMask != null)
            {
                smallFramesAlpha![fi] = LinearDownscale(alphaMask, targetW, targetH);

                using var edgeMask = CreateEdgeMask(alphaMask, bw);
                smallFramesEdge![fi] = LinearDownscale(edgeMask, targetW, targetH);

                if (smallFramesSdf != null)
                    smallFramesSdf[fi] = ComputeSdf(alphaMask, targetW, targetH, bw);

                alphaMask.Dispose();
            }

            var count = Interlocked.Increment(ref processed);
            if (count % 20 == 0 || count == frames.Length)
                Console.WriteLine($"  帧 {count}/{frames.Length}");
        });

        for (int i = 0; i < frames.Length; i++)
            frames[i].Dispose();

        // 去重
        Console.WriteLine("帧去重...");
        var uniqueIndices = new List<int> { 0 };
        for (int i = 1; i < smallFrames.Length; i++)
        {
            if (!FramesAlmostEqual(smallFrames[i - 1], smallFrames[i], targetW, targetH, dupThreshold))
                uniqueIndices.Add(i);
        }
        int dupCount = smallFrames.Length - uniqueIndices.Count;
        Console.WriteLine($"  去重: {smallFrames.Length} → {uniqueIndices.Count} 帧（跳过 {dupCount} 重复帧）");

        // 保存 GIF
        Console.WriteLine("保存 GIF...");
        int baseDelayCs = fpsVal.HasValue ? Math.Max(2, 1000 / fpsVal.Value / 10) : 4;
        int totalFrames = smallFrames.Length;

        SaveGifAnimation(smallFrames, uniqueIndices, totalFrames, output, baseDelayCs);
        Console.WriteLine($"已保存: {output} ({uniqueIndices.Count} 帧（原 {frames.Length}）, {targetW}x{targetH}, {palette.Count} 色)");

        string dir = Path.GetDirectoryName(output) ?? "";
        string eName = Path.GetFileNameWithoutExtension(output);
        string eExt = Path.GetExtension(output);

        if (needMask)
        {
            // Alpha GIF
            var alphaPath = Path.Combine(dir, eName + "_alpha" + eExt);
            SaveGifAnimation(smallFramesAlpha!, uniqueIndices, totalFrames, alphaPath, baseDelayCs);
            Console.WriteLine($"已保存: {alphaPath} ({uniqueIndices.Count} 帧) - Alpha 遮罩");

            // Edge GIF
            var edgePath = Path.Combine(dir, eName + "_edge" + eExt);
            SaveGifAnimation(smallFramesEdge!, uniqueIndices, totalFrames, edgePath, baseDelayCs);
            Console.WriteLine($"已保存: {edgePath} ({uniqueIndices.Count} 帧) - 边缘图");

            // SDF GIF
            if (smallFramesSdf != null)
            {
                var sdfPath = Path.Combine(dir, eName + "_sdf" + eExt);
                SaveGifAnimation(smallFramesSdf, uniqueIndices, totalFrames, sdfPath, baseDelayCs);
                Console.WriteLine($"已保存: {sdfPath} ({uniqueIndices.Count} 帧) - SDF 图");
            }
        }

        for (int i = 0; i < smallFrames.Length; i++)
        {
            smallFrames[i].Dispose();
            smallFramesAlpha?[i].Dispose();
            smallFramesEdge?[i].Dispose();
            smallFramesSdf?[i].Dispose();
        }

        // 保存 JSON
        var paletteHexOut = string.Join("", palette.Select(c =>
            c.A == 0 ? "000000" : $"{c.R:X2}{c.G:X2}{c.B:X2}"));
        var summaryPath = Path.ChangeExtension(output, ".json");
        var json = new JsonObject
        {
            ["source"] = Path.GetFileName(videoPath),
            ["frameCount"] = frames.Length,
            ["uniqueFrameCount"] = uniqueIndices.Count,
            ["frameSize"] = new JsonObject { ["width"] = targetW, ["height"] = targetH },
            ["sourceFrameSize"] = new JsonObject { ["width"] = firstFrame.Width, ["height"] = firstFrame.Height },
            ["scale"] = new JsonObject { ["x"] = Math.Round(scaleX, 2), ["y"] = Math.Round(scaleY, 2) },
            ["paletteCount"] = palette.Count,
            ["palette"] = paletteHexOut,
        };
        File.WriteAllText(summaryPath, json.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"已保存: {summaryPath}");

        if (!keepFrames)
        {
            Directory.Delete(tempDir, true);
            Console.WriteLine("已清理临时帧文件");
        }
        else
        {
            Console.WriteLine($"原始帧保留在: {tempDir}");
        }

        return 0;
    }

    #endregion

    #region 辅助方法

    static void SaveJson(string output, string inputPath, (int w, int h) originalSize,
        int smallW, int smallH, int uniqueColors, int paletteCount, bool hasAlpha, List<Rgba32> palette)
    {
        var jsonPath = Path.ChangeExtension(output, ".json");
        var paletteHex = string.Join("", palette.Select(c =>
            c.A == 0 ? "000000" : $"{c.R:X2}{c.G:X2}{c.B:X2}"));
        var json = new JsonObject
        {
            ["source"] = Path.GetFileName(inputPath),
            ["originalSize"] = new JsonObject { ["width"] = originalSize.w, ["height"] = originalSize.h },
            ["smallSize"] = new JsonObject { ["width"] = smallW, ["height"] = smallH },
            ["uniqueColors"] = uniqueColors,
            ["paletteCount"] = paletteCount,
            ["hasAlpha"] = hasAlpha,
            ["palette"] = paletteHex,
        };
        File.WriteAllText(jsonPath, json.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"已保存: {jsonPath}");
    }

    static List<Rgba32> ParsePaletteFromHex(string hex)
    {
        if (hex.Length % 6 != 0)
            throw new CliException($"调色板 hex 长度必须是 6 的倍数，当前: {hex.Length}");

        var palette = new List<Rgba32>();
        for (int i = 0; i < hex.Length; i += 6)
        {
            byte r = Convert.ToByte(hex.Substring(i, 2), 16);
            byte g = Convert.ToByte(hex.Substring(i + 2, 2), 16);
            byte b = Convert.ToByte(hex.Substring(i + 4, 2), 16);
            if (palette.Count == 0 && r == 0 && g == 0 && b == 0)
                palette.Add(new Rgba32(0, 0, 0, 0));
            else
                palette.Add(new Rgba32(r, g, b, 255));
        }
        return palette;
    }

    static bool FramesAlmostEqual(Image<Rgba32> a, Image<Rgba32> b, int w, int h, double threshold)
    {
        int fw = Math.Min(Math.Min(a.Width, b.Width), w);
        int fh = Math.Min(Math.Min(a.Height, b.Height), h);
        int total = fw * fh;
        int same = 0;
        for (int y = 0; y < fh; y++)
            for (int x = 0; x < fw; x++)
                if (a[x, y].PackedValue == b[x, y].PackedValue)
                    same++;
        return (double)same / total >= threshold;
    }

    static Image<Rgba32> RemapImageWithLabs(Image<Rgba32> image, List<Rgba32> palette, (double L, double a, double b)?[] paletteLabs)
    {
        var result = new Image<Rgba32>(image.Width, image.Height);

        for (int y = 0; y < image.Height; y++)
        {
            for (int x = 0; x < image.Width; x++)
            {
                var p = image[x, y];

                if (p.A < 128 && palette[0].A == 0)
                {
                    result[x, y] = palette[0];
                    continue;
                }

                var lab = RgbToLab(p.R, p.G, p.B);

                int best = 0;
                double bestD = double.MaxValue;
                for (int i = 0; i < paletteLabs.Length; i++)
                {
                    if (paletteLabs[i] == null) continue;
                    double d = LabDistance(lab, paletteLabs[i]!.Value);
                    if (d < bestD) { bestD = d; best = i; }
                }

                result[x, y] = palette[best];
            }
        }

        return result;
    }

    static void RunFfmpegExtract(string ffmpeg, string video, string outputDir, int? fps)
    {
        var args = $"-i \"{video}\" -y";
        if (fps.HasValue)
            args += $" -r {fps.Value}";
        args += $" \"{Path.Combine(outputDir, "frame_%06d.png")}\"";

        Console.WriteLine($"执行: {ffmpeg} {args}");

        var psi = new ProcessStartInfo
        {
            FileName = ffmpeg,
            Arguments = args,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        using var proc = Process.Start(psi) ?? throw new CliException($"无法启动 ffmpeg: {ffmpeg}");

        var stderr = proc.StandardError.ReadToEnd();
        proc.WaitForExit(300000);

        if (proc.ExitCode != 0)
            throw new CliException($"ffmpeg 退出码 {proc.ExitCode}: {stderr[^500..]}");
    }

    static void SaveGifAnimation(Image<Rgba32>[] allFrames, List<int> indices, int totalFrameCount, string path, int baseDelayCs)
    {
        using var gif = allFrames[indices[0]].CloneAs<Rgba32>();
        for (int i = 1; i < indices.Count; i++)
            gif.Frames.AddFrame(allFrames[indices[i]].Frames.RootFrame);

        for (int i = 0; i < indices.Count; i++)
        {
            int span = i < indices.Count - 1 ? indices[i + 1] - indices[i] : totalFrameCount - indices[i];
            var meta = gif.Frames[i].Metadata.GetGifMetadata();
            meta.FrameDelay = baseDelayCs * span;
            meta.DisposalMethod = GifDisposalMethod.RestoreToBackground;
        }

        gif.Metadata.GetGifMetadata().RepeatCount = 0; // 无限循环
        gif.Save(path, new GifEncoder());
    }

    #endregion

    #region 透明检测

    static bool DetectAlpha(Image<Rgba32> image)
    {
        for (int y = 0; y < image.Height; y++)
            for (int x = 0; x < image.Width; x++)
                if (image[x, y].A < 255)
                    return true;
        return false;
    }

    #endregion

    #region 最小调色板提取

    static List<Rgba32> ExtractMinimalPalette(Image<Rgba32> image, string algo, int maxColors, double threshold, bool hasAlpha, bool removeBg, out int uniqueColors)
    {
        var colorFreq = new Dictionary<int, (long sumR, long sumG, long sumB, int count)>();
        bool foundAlpha = false;

        for (int y = 0; y < image.Height; y++)
        {
            for (int x = 0; x < image.Width; x++)
            {
                var p = image[x, y];
                if (p.A < 128)
                {
                    foundAlpha = true;
                    continue;
                }
                int key = ((p.R & 0xF8) << 10) | ((p.G & 0xFC) << 3) | (p.B >> 3);
                if (colorFreq.TryGetValue(key, out var existing))
                    colorFreq[key] = (existing.sumR + p.R, existing.sumG + p.G, existing.sumB + p.B, existing.count + 1);
                else
                    colorFreq[key] = (p.R, p.G, p.B, 1);
            }
        }

        var avgColorFreq = new Dictionary<int, int>();
        foreach (var kvp in colorFreq)
        {
            var (sumR, sumG, sumB, count) = kvp.Value;
            byte r = (byte)Math.Round((double)sumR / count);
            byte g = (byte)Math.Round((double)sumG / count);
            byte b = (byte)Math.Round((double)sumB / count);
            int avgKey = (r << 16) | (g << 8) | b;
            avgColorFreq.TryGetValue(avgKey, out var cnt);
            avgColorFreq[avgKey] = cnt + count;
        }

        uniqueColors = avgColorFreq.Count + (foundAlpha ? 1 : 0);
        Console.WriteLine($"  唯一颜色(RGB565量化后): {avgColorFreq.Count}{(foundAlpha ? "+透明" : "")}");

        List<ColorCluster> result = algo switch
        {
            "cluster" => PaletteCluster(avgColorFreq, maxColors, threshold),
            "greedy" => PaletteGreedy(avgColorFreq, maxColors, threshold),
            _ => throw new CliException($"未知算法: {algo}，可选: cluster, greedy")
        };

        var sorted = result
            .OrderBy(c => c.Lab.L + c.Lab.a * 0.01 + c.Lab.b * 0.01)
            .Select(c => new Rgba32(c.Color.R, c.Color.G, c.Color.B, (byte)255))
            .ToList();

        if (hasAlpha || removeBg)
            sorted.Insert(0, new Rgba32(0, 0, 0, 0));

        return sorted;
    }

    static List<ColorCluster> PreQuantizeClusters(Dictionary<int, int> colorFreq, int step)
    {
        var merged = new Dictionary<int, ColorCluster>();

        foreach (var kvp in colorFreq)
        {
            int v = kvp.Key;
            byte r = (byte)(v >> 16), g = (byte)(v >> 8), b = (byte)v;

            byte qr = (byte)Math.Min(255, Math.Round(r / (double)step) * step);
            byte qg = (byte)Math.Min(255, Math.Round(g / (double)step) * step);
            byte qb = (byte)Math.Min(255, Math.Round(b / (double)step) * step);

            int key = (qr << 16) | (qg << 8) | qb;
            if (!merged.TryGetValue(key, out var existing))
                merged[key] = new ColorCluster(RgbToLab(qr, qg, qb), new Rgb24(qr, qg, qb), kvp.Value);
            else
            {
                int total = existing.Count + kvp.Value;
                byte mr = (byte)Math.Round((double)(existing.Color.R * existing.Count + r * kvp.Value) / total);
                byte mg = (byte)Math.Round((double)(existing.Color.G * existing.Count + g * kvp.Value) / total);
                byte mb = (byte)Math.Round((double)(existing.Color.B * existing.Count + b * kvp.Value) / total);
                merged[key] = new ColorCluster(RgbToLab(mr, mg, mb), new Rgb24(mr, mg, mb), total);
            }
        }

        return merged.Values.OrderByDescending(c => c.Count).ToList();
    }

    static ColorCluster MergeClusters(ColorCluster a, ColorCluster b)
    {
        int total = a.Count + b.Count;
        byte r = (byte)Math.Round((double)(a.Color.R * a.Count + b.Color.R * b.Count) / total);
        byte g = (byte)Math.Round((double)(a.Color.G * a.Count + b.Color.G * b.Count) / total);
        byte bv = (byte)Math.Round((double)(a.Color.B * a.Count + b.Color.B * b.Count) / total);
        return new ColorCluster(RgbToLab(r, g, bv), new Rgb24(r, g, bv), total);
    }

    static List<ColorCluster> PaletteCluster(Dictionary<int, int> colorFreq, int maxColors, double threshold)
    {
        int step = 32;
        var clusters = PreQuantizeClusters(colorFreq, step);
        Console.WriteLine($"  预量化(step={step}): {clusters.Count} 色");

        int mergeCount = 0;
        while (clusters.Count > 1)
        {
            double minDist = double.MaxValue;
            int minI = -1, minJ = -1;

            for (int i = 0; i < clusters.Count; i++)
                for (int j = i + 1; j < clusters.Count; j++)
                {
                    double dist = LabDistance(clusters[i].Lab, clusters[j].Lab);
                    if (dist < minDist) { minDist = dist; minI = i; minJ = j; }
                }

            if (minDist >= threshold) break;

            clusters[minI] = MergeClusters(clusters[minI], clusters[minJ]);
            clusters.RemoveAt(minJ);
            mergeCount++;
        }
        Console.WriteLine($"  聚类合并: {mergeCount} 次 → {clusters.Count} 色");

        ForceReduce(clusters, maxColors);
        return clusters;
    }

    static List<ColorCluster> PaletteGreedy(Dictionary<int, int> colorFreq, int maxColors, double threshold)
    {
        var sorted = colorFreq
            .Select(kvp =>
            {
                int v = kvp.Key;
                return new ColorCluster(
                    RgbToLab((byte)(v >> 16), (byte)(v >> 8), (byte)v),
                    new Rgb24((byte)(v >> 16), (byte)(v >> 8), (byte)v),
                    kvp.Value);
            })
            .OrderByDescending(c => c.Count)
            .ToList();

        var palette = new List<ColorCluster>();

        foreach (var entry in sorted)
        {
            int bestIdx = -1;
            double bestDist = threshold;
            for (int i = 0; i < palette.Count; i++)
            {
                double dist = LabDistance(entry.Lab, palette[i].Lab);
                if (dist < bestDist) { bestDist = dist; bestIdx = i; }
            }

            if (bestIdx >= 0)
                palette[bestIdx] = MergeClusters(palette[bestIdx], entry);
            else if (palette.Count < maxColors)
                palette.Add(entry);
            else
            {
                double forcedBest = double.MaxValue;
                int forcedIdx = 0;
                for (int i = 0; i < palette.Count; i++)
                {
                    double dist = LabDistance(entry.Lab, palette[i].Lab);
                    if (dist < forcedBest) { forcedBest = dist; forcedIdx = i; }
                }
                palette[forcedIdx] = MergeClusters(palette[forcedIdx], entry);
            }
        }

        return palette;
    }

    static void ForceReduce(List<ColorCluster> clusters, int maxColors)
    {
        int forcedMerges = 0;
        while (clusters.Count > maxColors)
        {
            double minDist = double.MaxValue;
            int minI = 0, minJ = 1;

            for (int i = 0; i < clusters.Count; i++)
                for (int j = i + 1; j < clusters.Count; j++)
                {
                    double dist = LabDistance(clusters[i].Lab, clusters[j].Lab);
                    if (dist < minDist) { minDist = dist; minI = i; minJ = j; }
                }

            clusters[minI] = MergeClusters(clusters[minI], clusters[minJ]);
            clusters.RemoveAt(minJ);
            forcedMerges++;
        }

        if (forcedMerges > 0)
            Console.WriteLine($"  强制合并: {forcedMerges} 次 → {clusters.Count} 色");
    }

    #endregion

    #region 调色板清理图像

    static Image<Rgba32> RemapImage(Image<Rgba32> image, List<Rgba32> palette)
    {
        var paletteLabs = new (double L, double a, double b)?[palette.Count];
        for (int i = 0; i < palette.Count; i++)
        {
            var c = palette[i];
            paletteLabs[i] = c.A == 0 ? null : RgbToLab(c.R, c.G, c.B);
        }

        var result = new Image<Rgba32>(image.Width, image.Height);

        for (int y = 0; y < image.Height; y++)
        {
            for (int x = 0; x < image.Width; x++)
            {
                var p = image[x, y];

                if (p.A < 128 && palette[0].A == 0)
                {
                    result[x, y] = palette[0];
                    continue;
                }

                var lab = RgbToLab(p.R, p.G, p.B);

                int best = 0;
                double bestD = double.MaxValue;
                for (int i = 0; i < paletteLabs.Length; i++)
                {
                    if (paletteLabs[i] == null) continue;
                    double d = LabDistance(lab, paletteLabs[i]!.Value);
                    if (d < bestD) { bestD = d; best = i; }
                }

                result[x, y] = palette[best];
            }
        }

        return result;
    }

    #endregion

    #region 投票法降采样

    static Image<Rgba32> DownscaleVote(Image<Rgba32> cleaned, int scaleX, int scaleY, List<Rgba32> palette)
    {
        int newW = cleaned.Width / scaleX;
        int newH = cleaned.Height / scaleY;
        var result = new Image<Rgba32>(newW, newH);

        var paletteIdx = new Dictionary<uint, int>();
        for (int i = 0; i < palette.Count; i++)
            paletteIdx[PackRgba(palette[i])] = i;

        for (int by = 0; by < newH; by++)
        {
            for (int bx = 0; bx < newW; bx++)
            {
                var votes = new Dictionary<int, int>();

                for (int dy = 0; dy < scaleY; dy++)
                    for (int dx = 0; dx < scaleX; dx++)
                    {
                        int idx = paletteIdx.TryGetValue(PackRgba(cleaned[bx * scaleX + dx, by * scaleY + dy]), out var i) ? i : -1;
                        if (idx < 0) continue;
                        votes.TryGetValue(idx, out var cnt);
                        votes[idx] = cnt + 1;
                    }

                if (votes.Count == 0) continue;
                int bestIdx = votes.OrderByDescending(kvp => kvp.Value).First().Key;
                result[bx, by] = palette[bestIdx];
            }
        }

        return result;
    }

    #endregion

    #region 删除背景 + Alpha Mask

    /// <summary>
    /// 在大图 clean 图上：将左上角颜色及相近颜色设为 transparent，同时生成 alpha mask。
    /// 先标记所有精确匹配背景色的像素，再 BFS 扩展到相邻且颜色接近（≤ threshold*2）的像素。
    /// 修改 image 原地，返回 alpha mask（大图尺寸）。
    /// </summary>
    static Image<Rgba32> RemoveBgCreateMask(Image<Rgba32> image, List<Rgba32> palette, double threshold)
    {
        var bgColor = image[0, 0];
        uint bgPacked = PackRgba(bgColor);
        var bgLab = RgbToLab(bgColor.R, bgColor.G, bgColor.B);
        double expandThreshold = threshold * 2;

        // 预计算调色板中哪些颜色与背景色接近
        var bgLikeSet = new HashSet<uint> { bgPacked };
        foreach (var c in palette)
        {
            if (c.A == 0) continue;
            if (LabDistance(RgbToLab(c.R, c.G, c.B), bgLab) <= expandThreshold)
                bgLikeSet.Add(PackRgba(c));
        }

        Console.WriteLine($"  背景色: #{bgColor.R:X2}{bgColor.G:X2}{bgColor.B:X2}, 相似色: {bgLikeSet.Count} 种 (阈值: {expandThreshold:F1})");

        int w = image.Width, h = image.Height;
        var isBg = new bool[w, h];
        var queue = new Queue<(int x, int y)>();
        int exactCount = 0;

        // 种子：所有精确匹配背景色的像素
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                if (PackRgba(image[x, y]) == bgPacked)
                {
                    isBg[x, y] = true;
                    queue.Enqueue((x, y));
                    exactCount++;
                }

        // BFS：扩展到相邻的相似色像素
        while (queue.Count > 0)
        {
            var (cx, cy) = queue.Dequeue();
            if (cx > 0 && !isBg[cx - 1, cy] && bgLikeSet.Contains(PackRgba(image[cx - 1, cy])))
            { isBg[cx - 1, cy] = true; queue.Enqueue((cx - 1, cy)); }
            if (cx < w - 1 && !isBg[cx + 1, cy] && bgLikeSet.Contains(PackRgba(image[cx + 1, cy])))
            { isBg[cx + 1, cy] = true; queue.Enqueue((cx + 1, cy)); }
            if (cy > 0 && !isBg[cx, cy - 1] && bgLikeSet.Contains(PackRgba(image[cx, cy - 1])))
            { isBg[cx, cy - 1] = true; queue.Enqueue((cx, cy - 1)); }
            if (cy < h - 1 && !isBg[cx, cy + 1] && bgLikeSet.Contains(PackRgba(image[cx, cy + 1])))
            { isBg[cx, cy + 1] = true; queue.Enqueue((cx, cy + 1)); }
        }

        // 应用：设为 transparent，生成 mask
        var mask = new Image<Rgba32>(w, h);
        int removedPixels = 0;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                if (isBg[x, y])
                {
                    image[x, y] = palette[0];
                    removedPixels++;
                }
                byte v = isBg[x, y] ? (byte)0 : (byte)255;
                mask[x, y] = new Rgba32(v, v, v, 255);
            }

        Console.WriteLine($"  删除背景: {removedPixels} 像素 (精确: {exactCount}, 扩展: {removedPixels - exactCount})");
        return mask;
    }

    #endregion

    #region Alpha/Edge/SDF 辅助图

    static Image<Rgba32> CreateEdgeMask(Image<Rgba32> alphaMask, int blockWidth)
    {
        int w = alphaMask.Width, h = alphaMask.Height;

        // 提取布尔遮罩
        var mask = new bool[w, h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                mask[x, y] = alphaMask[x, y].R > 128;

        // 迭代腐蚀 blockWidth 轮
        var eroded = (bool[,])mask.Clone();
        for (int round = 0; round < blockWidth; round++)
        {
            var next = new bool[w, h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    if (!eroded[x, y]) continue;
                    // 四邻域都必须为 true 才保留
                    bool allInside = true;
                    if (x <= 0 || !eroded[x - 1, y]) allInside = false;
                    else if (x >= w - 1 || !eroded[x + 1, y]) allInside = false;
                    else if (y <= 0 || !eroded[x, y - 1]) allInside = false;
                    else if (y >= h - 1 || !eroded[x, y + 1]) allInside = false;
                    next[x, y] = allInside;
                }
            eroded = next;
        }

        // XOR：原遮罩 - 腐蚀结果 = 边界区域
        var result = new Image<Rgba32>(w, h);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                bool isEdge = mask[x, y] && !eroded[x, y];
                byte v = isEdge ? (byte)255 : (byte)0;
                result[x, y] = new Rgba32(v, v, v, 255);
            }

        return result;
    }

    static Image<Rgba32> LinearDownscale(Image<Rgba32> image, int targetW, int targetH)
    {
        var result = image.Clone();
        result.Mutate(x => x.Resize(targetW, targetH, KnownResamplers.Triangle));
        return result;
    }

    static Image<Rgba32> ComputeSdf(Image<Rgba32> alphaMask, int targetW, int targetH, int blockWidth)
    {
        int w = alphaMask.Width, h = alphaMask.Height;

        // 提取布尔遮罩
        var mask = new bool[w, h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                mask[x, y] = alphaMask[x, y].R > 128;

        // 收集边界像素（白色像素且四邻域有黑色像素）
        var boundaryPixels = new List<(int x, int y)>();
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                if (!mask[x, y]) continue;
                bool isBoundary = false;
                if (x <= 0 || !mask[x - 1, y]) isBoundary = true;
                else if (x >= w - 1 || !mask[x + 1, y]) isBoundary = true;
                else if (y <= 0 || !mask[x, y - 1]) isBoundary = true;
                else if (y >= h - 1 || !mask[x, y + 1]) isBoundary = true;
                if (isBoundary)
                    boundaryPixels.Add((x, y));
            }

        // 也收集遮罩外侧的边界像素
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                if (mask[x, y]) continue;
                bool adjInside = false;
                if (x > 0 && mask[x - 1, y]) adjInside = true;
                else if (x < w - 1 && mask[x + 1, y]) adjInside = true;
                else if (y > 0 && mask[x, y - 1]) adjInside = true;
                else if (y < h - 1 && mask[x, y + 1]) adjInside = true;
                if (adjInside)
                    boundaryPixels.Add((x, y));
            }

        // 建立网格空间索引
        int cellSize = Math.Max(1, blockWidth);
        int cellsX = (w + cellSize - 1) / cellSize;
        int cellsY = (h + cellSize - 1) / cellSize;
        var grid = new List<(int x, int y)>[cellsX, cellsY];
        foreach (var (bx, by) in boundaryPixels)
        {
            int cx = Math.Min(bx / cellSize, cellsX - 1);
            int cy = Math.Min(by / cellSize, cellsY - 1);
            grid[cx, cy] ??= new List<(int x, int y)>();
            grid[cx, cy].Add((bx, by));
        }

        // 计算每个小图像素的 SDF
        double scaleX = (double)w / targetW;
        double scaleY = (double)h / targetH;
        var result = new Image<Rgba32>(targetW, targetH);

        for (int ty = 0; ty < targetH; ty++)
        {
            for (int tx = 0; tx < targetW; tx++)
            {
                double srcX = (tx + 0.5) * scaleX;
                double srcY = (ty + 0.5) * scaleY;
                int srcXi = (int)srcX, srcYi = (int)srcY;

                bool inside = srcXi >= 0 && srcXi < w && srcYi >= 0 && srcYi < h && mask[srcXi, srcYi];

                // 搜索最近边界像素（使用空间索引加速）
                int centerCx = Math.Min(Math.Max((int)(srcX / cellSize), 0), cellsX - 1);
                int centerCy = Math.Min(Math.Max((int)(srcY / cellSize), 0), cellsY - 1);

                double minDistSq = double.MaxValue;
                // 逐步扩大搜索范围
                for (int radius = 0; radius <= cellsX + cellsY; radius++)
                {
                    if (minDistSq < double.MaxValue) break; // 已找到候选

                    for (int dx = -radius; dx <= radius; dx++)
                    {
                        for (int dy = -radius; dy <= radius; dy++)
                        {
                            if (Math.Abs(dx) != radius && Math.Abs(dy) != radius) continue;
                            int gx = centerCx + dx, gy = centerCy + dy;
                            if (gx < 0 || gx >= cellsX || gy < 0 || gy >= cellsY) continue;
                            var cell = grid[gx, gy];
                            if (cell == null) continue;
                            foreach (var (bx, by) in cell)
                            {
                                double dsq = (bx - srcX) * (bx - srcX) + (by - srcY) * (by - srcY);
                                if (dsq < minDistSq) minDistSq = dsq;
                            }
                        }
                    }
                }

                if (minDistSq == double.MaxValue) minDistSq = 0;
                double dist = Math.Sqrt(minDistSq);
                double sdf = inside ? dist / blockWidth : -dist / blockWidth;

                // 编码为灰度：128 = 边界，>128 = 内部，<128 = 外部，1 小像素 ≈ 8 灰度级
                byte gray = (byte)Math.Clamp(128 + sdf * 8, 0, 255);
                result[tx, ty] = new Rgba32(gray, gray, gray, 255);
            }
        }

        return result;
    }

    #endregion

    #region Lab 色彩空间

    static (double L, double a, double b) RgbToLab(byte r, byte g, byte bv)
    {
        double rl = SrgbToLinear(r / 255.0);
        double gl = SrgbToLinear(g / 255.0);
        double bl = SrgbToLinear(bv / 255.0);

        double x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375;
        double y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750;
        double z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041;

        x /= 0.95047;
        y /= 1.00000;
        z /= 1.08883;

        return (116.0 * LabF(y) - 16.0, 500.0 * (LabF(x) - LabF(y)), 200.0 * (LabF(y) - LabF(z)));
    }

    static double SrgbToLinear(double c) =>
        c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);

    static double LabF(double t) =>
        t > 0.008856 ? Math.Pow(t, 1.0 / 3.0) : (903.3 * t + 16.0) / 116.0;

    static double LabDistance((double L, double a, double b) c1, (double L, double a, double b) c2)
    {
        double dL = c1.L - c2.L, da = c1.a - c2.a, db = c1.b - c2.b;
        return Math.Sqrt(dL * dL + da * da + db * db);
    }

    #endregion

    #region CLI Helpers

    static int PackRgb(Rgb24 c) => (c.R << 16) | (c.G << 8) | c.B;
    static uint PackRgba(Rgba32 c) => (uint)(c.R << 24 | c.G << 16 | c.B << 8 | c.A);

    static string? GetPositionalArg(string[] args) =>
        args.FirstOrDefault(a => !a.StartsWith("-"));

    static string ParseRequired(string[] args, string name) =>
        ParseOptional(args, name) ?? throw new CliException($"缺少必填参数: {name}");

    static string? ParseOptional(string[] args, string name)
    {
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i] == name) return args[i + 1];
        return null;
    }

    static bool HasFlag(string[] args, string flag) => args.Contains(flag);

    static int ParseInt(string[] args, string name, int defaultValue)
    {
        var v = ParseOptional(args, name);
        return v != null && int.TryParse(v, out var n) ? n : defaultValue;
    }

    static int? ParseNullableInt(string[] args, string name)
    {
        var v = ParseOptional(args, name);
        return v != null && int.TryParse(v, out var n) ? n : null;
    }

    static double ParseDouble(string[] args, string name, double defaultValue)
    {
        var v = ParseOptional(args, name);
        return v != null && double.TryParse(v, out var n) ? n : defaultValue;
    }

    static int Fail(string msg)
    {
        Console.Error.WriteLine($"错误: {msg}");
        return 1;
    }

    #endregion
}

record struct ColorCluster((double L, double a, double b) Lab, Rgb24 Color, int Count);

class CliException : Exception
{
    public CliException(string message) : base(message) { }
}
