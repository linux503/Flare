# Flare Windows (WPF)

Windows 原生版本（WPF + WebView2）实验工程。

## 当前能力

- 输入网页 URL 并加载
- 自动滚动网页并分段截图
- 自动拼接为一张长图
- 导出 PNG

## 运行

1. 用 Visual Studio 2022 打开 `FlareWpf.csproj`
2. 目标框架 `net8.0-windows`
3. 运行后输入 URL，点击「自动长截图」

## 说明

- 当前仅支持 **网页长截图**（WebView2 页面）
- 非网页应用窗口自动滚动不在本工程范围
