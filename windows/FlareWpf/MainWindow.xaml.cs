using FlareWpf.Services;
using Microsoft.Web.WebView2.Core;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace FlareWpf;

public partial class MainWindow : Window
{
    private byte[]? _lastPng;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            await Browser.EnsureCoreWebView2Async();
            Browser.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;
        };
    }

    private void OpenBtn_OnClick(object sender, RoutedEventArgs e)
    {
        if (Browser.CoreWebView2 is null) return;
        if (!Uri.TryCreate(UrlBox.Text.Trim(), UriKind.Absolute, out var uri))
        {
            StatusText.Text = "URL 无效";
            return;
        }
        Browser.CoreWebView2.Navigate(uri.ToString());
        StatusText.Text = "正在加载网页…";
    }

    private async void CaptureBtn_OnClick(object sender, RoutedEventArgs e)
    {
        if (Browser.CoreWebView2 is null) return;
        CaptureBtn.IsEnabled = false;
        SaveBtn.IsEnabled = false;
        StatusText.Text = "正在自动滚动并拼接…";

        try
        {
            _lastPng = await LongScreenshotService.CaptureWebPageAsync(Browser.CoreWebView2);
            using var ms = new MemoryStream(_lastPng);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.StreamSource = ms;
            bitmap.EndInit();
            bitmap.Freeze();
            PreviewImage.Source = bitmap;
            SaveBtn.IsEnabled = true;
            StatusText.Text = "长截图完成。";
        }
        catch (Exception ex)
        {
            StatusText.Text = $"长截图失败：{ex.Message}";
        }
        finally
        {
            CaptureBtn.IsEnabled = true;
        }
    }

    private void SaveBtn_OnClick(object sender, RoutedEventArgs e)
    {
        if (_lastPng is null) return;
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Filter = "PNG Image|*.png",
            FileName = $"Flare-LongScreenshot-{DateTime.Now:yyyyMMdd-HHmmss}.png"
        };
        if (dialog.ShowDialog(this) != true) return;
        File.WriteAllBytes(dialog.FileName, _lastPng);
        StatusText.Text = $"已保存：{Path.GetFileName(dialog.FileName)}";
    }
}
