using Microsoft.Web.WebView2.Core;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Text.Json;

namespace FlareWpf.Services;

internal static class LongScreenshotService
{
    public static async Task<byte[]> CaptureWebPageAsync(CoreWebView2 webView)
    {
        var metricsJson = await webView.ExecuteScriptAsync(
            "JSON.stringify({h: document.documentElement.scrollHeight, vh: window.innerHeight, y: window.scrollY})");
        var metrics = JsonSerializer.Deserialize<WebMetrics>(Unquote(metricsJson)) ?? new WebMetrics();

        int total = Math.Max(metrics.h, metrics.vh);
        int viewport = Math.Max(metrics.vh, 1);
        int step = Math.Max((int)(viewport * 0.8), 1);

        var parts = new List<Bitmap>();
        try
        {
            await webView.ExecuteScriptAsync("window.scrollTo(0, 0)");
            await Task.Delay(350);

            int y = 0;
            int guard = 0;
            while (y < total && guard < 60)
            {
                parts.Add(await CaptureViewportAsync(webView));
                y += step;
                await webView.ExecuteScriptAsync($"window.scrollTo(0, {y})");
                await Task.Delay(260);
                guard++;
            }

            if (parts.Count == 0) throw new InvalidOperationException("没有捕获到可用画面");
            var stitched = Stitch(parts);
            using var outMs = new MemoryStream();
            stitched.Save(outMs, ImageFormat.Png);
            return outMs.ToArray();
        }
        finally
        {
            foreach (var p in parts) p.Dispose();
        }
    }

    private static async Task<Bitmap> CaptureViewportAsync(CoreWebView2 webView)
    {
        using var ms = new MemoryStream();
        await webView.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, ms);
        ms.Position = 0;
        return new Bitmap(ms);
    }

    private static Bitmap Stitch(IReadOnlyList<Bitmap> parts)
    {
        int width = parts[0].Width;
        int totalHeight = parts.Sum(p => p.Height);
        var output = new Bitmap(width, totalHeight, PixelFormat.Format32bppArgb);

        using var g = Graphics.FromImage(output);
        g.Clear(Color.White);

        int y = 0;
        for (int i = 0; i < parts.Count; i++)
        {
            var part = parts[i];
            int overlap = i == 0 ? 0 : EstimateOverlap(parts[i - 1], part);
            g.DrawImage(part, new Rectangle(0, y - overlap, part.Width, part.Height));
            y += part.Height - overlap;
        }

        if (y <= 0) return output;
        if (y == output.Height) return output;

        var cropped = new Bitmap(width, y, PixelFormat.Format32bppArgb);
        using var cg = Graphics.FromImage(cropped);
        cg.DrawImage(output, new Rectangle(0, 0, width, y), new Rectangle(0, 0, width, y), GraphicsUnit.Pixel);
        output.Dispose();
        return cropped;
    }

    private static int EstimateOverlap(Bitmap a, Bitmap b)
    {
        int max = Math.Min(a.Height, b.Height);
        int min = Math.Max(20, (int)(max * 0.10));
        int top = Math.Max(min, (int)(max * 0.40));

        double best = double.MaxValue;
        int bestOverlap = min;
        for (int overlap = min; overlap <= top; overlap += 4)
        {
            double score = 0;
            int sampleRows = Math.Max(1, overlap / 8);
            int sampleCols = Math.Max(1, a.Width / 80);

            for (int ry = 0; ry < sampleRows; ry++)
            {
                int ay = a.Height - overlap + ry * 8;
                int by = ry * 8;
                for (int x = 0; x < a.Width; x += sampleCols)
                {
                    var pa = a.GetPixel(x, ay);
                    var pb = b.GetPixel(x, by);
                    score += Math.Abs(pa.R - pb.R) + Math.Abs(pa.G - pb.G) + Math.Abs(pa.B - pb.B);
                }
            }

            if (score < best)
            {
                best = score;
                bestOverlap = overlap;
            }
        }
        return bestOverlap;
    }

    private static string Unquote(string jsonString)
    {
        if (jsonString.StartsWith("\"") && jsonString.EndsWith("\""))
            return jsonString[1..^1].Replace("\\\"", "\"");
        return jsonString;
    }

    private sealed class WebMetrics
    {
        public int h { get; set; }
        public int vh { get; set; }
        public int y { get; set; }
    }
}
