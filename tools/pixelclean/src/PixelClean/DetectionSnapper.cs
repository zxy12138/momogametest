using System.Diagnostics;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Formats.Png;

namespace PixelAnalyzer;

/// <summary>
/// 使用 spritefusion-pixel-snapper 外部工具探测小图尺寸。
/// 调用 snapper 对图像降采样，直接返回输出图的小图尺寸。
/// </summary>
static partial class Program
{
    /// <summary>
    /// 使用 snapper 探测小图尺寸。
    /// 返回 snapper 输出图的 (width, height)。
    /// </summary>
    static (int smallW, int smallH) DetectSmallSize(Image<Rgba32> image)
    {
        var snapperPath = FindTool("spritefusion-pixel-snapper.exe");

        // 保存输入图像到临时文件
        var tempInput = Path.Combine(Path.GetTempPath(), $"pixanalyze_snapper_{Guid.NewGuid():N}.png");
        var tempOutput = Path.Combine(Path.GetTempPath(), $"pixanalyze_snapper_{Guid.NewGuid():N}.png");
        try
        {
            image.Save(tempInput, new PngEncoder());

            // 调用: spritefusion-pixel-snapper.exe <input> <output> 16
            var args = $"\"{tempInput}\" \"{tempOutput}\" 16";
            Console.WriteLine($"执行: {snapperPath} {args}");

            var psi = new ProcessStartInfo
            {
                FileName = snapperPath,
                Arguments = args,
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };

            using var proc = Process.Start(psi) ?? throw new CliException($"无法启动 snapper: {snapperPath}");
            var stdout = proc.StandardOutput.ReadToEnd();
            var stderr = proc.StandardError.ReadToEnd();
            proc.WaitForExit(60000);

            if (proc.ExitCode != 0)
                throw new CliException($"snapper 退出码 {proc.ExitCode}: {stderr}");

            if (!File.Exists(tempOutput))
                throw new CliException($"snapper 未生成输出文件: {tempOutput}");

            // 读取输出图尺寸
            using var outputImage = Image.Load<Rgba32>(tempOutput);
            int outW = outputImage.Width;
            int outH = outputImage.Height;

            if (outW == 0 || outH == 0)
                throw new CliException($"snapper 输出尺寸异常: {outW}x{outH}");

            Console.WriteLine($"  snapper: {image.Width}x{image.Height} → {outW}x{outH}");

            return (outW, outH);
        }
        finally
        {
            try { if (File.Exists(tempInput)) File.Delete(tempInput); } catch { }
            try { if (File.Exists(tempOutput)) File.Delete(tempOutput); } catch { }
        }
    }

    /// <summary>
    /// 按 PATH → ./ → tool/ → ../tool/ → ../../tool/ 搜索工具，
    /// 所有路径都相对于 exe 所在目录。
    /// 返回第一个找到的完整路径，找不到则抛异常。
    /// </summary>
    static string FindTool(string exeName)
    {
        var exeDir = AppContext.BaseDirectory;

        // 搜索路径列表（相对于 exe 目录）
        string[] searchDirs =
        [
            "",                     // exe 旁边
            "tool",                 // exe所在目录/tool/
            "../tool",              // 上一级/tool/
            "../../tool",           // 上两级/tool/ (bin/Debug/tool)
            "../../../tool",        // 上三级/tool/ (项目根/tool)
            "../../../../tool",     // 上四级/tool/ (解决方案根/tool)
        ];

        foreach (var dir in searchDirs)
        {
            var candidate = Path.GetFullPath(Path.Combine(exeDir, dir, exeName));
            if (File.Exists(candidate))
            {
                Console.WriteLine($"  找到工具: {candidate}");
                return candidate;
            }
        }

        // 最后尝试 PATH 环境变量
        var pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(dir.Trim('"'), exeName);
                if (File.Exists(candidate))
                {
                    Console.WriteLine($"  找到工具 (PATH): {candidate}");
                    return candidate;
                }
            }
            catch { }
        }

        throw new CliException($"找不到工具: {exeName}（搜索路径: {string.Join(", ", searchDirs.Select(d => string.IsNullOrEmpty(d) ? "./" : d))}，以及 PATH 环境变量）");
    }
}
