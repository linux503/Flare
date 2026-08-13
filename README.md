# Flare Pro — 一拍即得

原生 macOS 截图工具。菜单栏单击即截图，支持 Apple Silicon + Intel。

## 用法（越少步骤越好）

| 操作 | 方式 |
|------|------|
| 区域截图 | **菜单栏图标单击**，或 ⌘⌥5 |
| 屏幕录制 | ⌘⌥R（录制中再按一次停止） |
| 更多功能 | 菜单栏图标**右键** |
| 确认选区 | 空格 / 回车 / 工具栏按钮 / 双击 |
| 主面板 | Dock 图标，或 ⌘O |

## 功能

- 区域 / 窗口 / 全屏 / 延时截图
- 屏幕录制（全屏 · H.264 MOV）
- 标注、OCR、钉图、历史
- 独立「新建文档」（TXT / Word / PPT / Excel 表格）
- 黑白半透明界面
- 在线检查更新、官网与 GitHub 链接

## 官网

- 站点：https://linux503.github.io/Flare/
- 源码：https://github.com/linux503/Flare
- App「设置 → 关于」可检查更新（读取 `docs/version.json`）

## 发布包

Universal DMG：构建后见 `dist/`（Apple Silicon + Intel）

## 构建

```bash
cd Flare
./Scripts/build.sh
./Scripts/install.sh   # 安装到 /Applications/Flare Pro.app
```

## 权限

1. 系统设置 → 隐私与安全性 → 屏幕录制 → 打开 **Flare Pro**（若仍显示旧名 Snap / Flare，打开那一项即可；Bundle ID 未变）
2. 完全退出再打开

推荐始终从 `/Applications/Flare Pro.app` 运行。
