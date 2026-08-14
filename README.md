# Flare Pro

**一拍即得** — 原生 macOS 截图与屏幕录制工具。

菜单栏单击即截，支持 **Apple Silicon** 与 **Intel**。轻、快、少步骤。

<p align="center">
  <a href="https://linux503.github.io/Flare/">官网</a> ·
  <a href="https://linux503.github.io/Flare/#download">下载</a> ·
  <a href="https://github.com/linux503/Flare/releases">Releases</a>
</p>

---

## 快速上手

| 你想做 | 怎么做 |
|--------|--------|
| 区域截图 | **菜单栏图标单击**，或 `⌘⌥5` |
| 窗口 / 全屏 / 延时 | 右键菜单栏图标，或主菜单「截图」 |
| 屏幕录制 | 菜单「录制」，或 `⌘⌥R`；录制中再按可停止 |
| 更多功能 | 菜单栏图标**右键** |
| 确认选区 | `空格` / `回车` / 工具栏 / 双击 |
| 主面板 | Dock 图标，或 `⌘O` |

---

## 功能一览

- **截图** — 区域、窗口、全屏、延时；取色放大镜与选区工具栏
- **录屏** — 全屏/区域；声音可选关闭 / 系统 / 麦克风；清晰度预设；倒计时、暂停；H.264 MOV
- **标注** — 箭头、高亮、马赛克、序号等
- **OCR** — 识字并导出文本
- **钉图 / 历史** — 钉在桌面，随时回看最近截图
- **新建文档** — TXT / Word / PPT / Excel 一键创建
- **界面** — 黑白半透明主题；在线检查更新

---

## 系统要求

- macOS **14.0** 及以上
- Universal Binary（arm64 + x86_64）

---

## 权限

1. **系统设置 → 隐私与安全性 → 屏幕与系统音频录制**
2. 打开 **Flare Pro**（若有灰色旧条目，先删除再重新勾选）
3. **完全退出**后再打开

推荐始终从 `/Applications/Flare Pro.app` 运行（不要直接跑 `dist/` 里的副本）。

构建脚本会用本机的 **Apple Development** 证书签名，授权一次后重新编译不用再开权限。若系统设置里有灰色旧条目，删掉再勾选一次即可。

---

## 构建

```bash
git clone https://github.com/linux503/Flare.git
cd Flare
./Scripts/build.sh
./Scripts/install.sh   # 安装到 /Applications/Flare Pro.app
```

构建产物在 `dist/`（含 Universal 应用；可按需打 DMG）。

---

## 官网与更新

| | |
|--|--|
| 站点 | https://linux503.github.io/Flare/ |
| 源码 | https://github.com/linux503/Flare |
| 更新源 | [`docs/version.json`](docs/version.json)（App「设置 → 关于」可检查更新） |

启用 GitHub Pages：仓库 Settings → Pages → Source 选 `main` / `/docs`。

---

## 许可证

个人使用与学习欢迎。商业分发请先联系仓库所有者。
