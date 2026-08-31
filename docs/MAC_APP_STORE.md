# Flare Pro 上架 Mac App Store

当前仓库已支持打 **Mac App Store 包**（沙盒版）。你这边钥匙串里暂时只有 **Apple Development**，还需要办完苹果后台手续后才能真正提交。

## 你现在的状态

| 项目 | 状态 |
|------|------|
| Bundle ID | `app.flare.screenshot` |
| 沙盒 entitlements | `Resources/Flare-MAS.entitlements`（已备好） |
| 打包脚本 | `./Scripts/make_mas.sh` |
| 本机证书 | 仅有 Apple Development ❌ 还缺 Distribution |

## 一、开通账号（若还没有）

1. 打开 [Apple Developer Program](https://developer.apple.com/programs/) 注册并付款（年费 $99）
2. 用同一账号登录 [App Store Connect](https://appstoreconnect.apple.com)

## 二、创建证书与描述文件

### 1. App ID

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+**
2. 选 **App IDs** → **App**
3. Description: `Flare Pro`
4. Bundle ID: **Explicit** → `app.flare.screenshot`
5. Capabilities 勾选：
   - **App Sandbox**
   - （可选）Associated Domains 等不要乱开

### 2. 证书（两张）

在 [Certificates](https://developer.apple.com/account/resources/certificates/list)：

1. **Apple Distribution**（给 .app 签名）  
   - 本机钥匙串打开「钥匙串访问」→ 证书助理 → 从证书颁发机构请求证书 → 存成 CSR  
   - 上传 CSR，下载 `.cer`，双击安装
2. **Mac Installer Distribution** / **3rd Party Mac Developer Installer**（给 .pkg 签名）  
   - 同样用 CSR 创建并安装

装好后在终端应能看到类似：

```bash
security find-identity -v -p codesigning | grep -E 'Distribution|Mac Developer'
```

### 3. 描述文件（Provisioning Profile）

1. [Profiles](https://developer.apple.com/account/resources/profiles/list) → **+**
2. 选 **Mac App Store Connect**（或 Mac App Store）
3. App ID 选 `app.flare.screenshot`
4. 勾选刚建的 Distribution 证书
5. 下载 `*.provisionprofile`
6. 保存为：

```text
Resources/Flare_MacAppStore.provisionprofile
```

## 三、在 App Store Connect 建 App

1. [我的 App](https://appstoreconnect.apple.com/apps) → **+** → **新建 App**
2. 平台勾选 **macOS**
3. 名称：`Flare Pro`（若被占用可改 `Flare Pro Screenshot` 等）
4. 主要语言：简体中文
5. Bundle ID：选 `app.flare.screenshot`
6. SKU：例如 `flare-pro-mac`

### 必填资料（审核用）

- **副标题 / 描述**：说明截图、录屏、OCR、长截图等
- **关键词**
- **支持 URL**：`https://linux503.github.io/Flare/`
- **隐私政策 URL**（没有的话需先加一页隐私政策到官网）
- **截图**：至少 1 张 Mac 截图（1280×800 或按后台要求尺寸）
- **App 分级**
- **出口合规**：本工程已在 Info.plist 写了 `ITSAppUsesNonExemptEncryption = false`（仅 HTTPS）

### 权限说明（审核备注建议粘贴）

```text
本 App 需要：
1. 屏幕录制：区域/窗口/全屏截图与录屏（ScreenCaptureKit）
2. 麦克风：录屏时可收录人声（可选）
3. 辅助功能：长截图时模拟滚动（Accessibility）
菜单栏常驻（LSUIElement），无主窗口也可以通过菜单栏图标打开面板。
```

## 四、本地打 MAS 包

证书和描述文件就绪后：

```bash
cd /Users/a503/Downloads/Mac-soft/Flare
./Scripts/make_mas.sh
```

成功后会得到：

- `dist/Flare Pro.app`（沙盒 + Distribution 签名）
- `dist/Flare-Pro-MAS.pkg`（可上传）

## 五、上传与提交

1. Mac App Store 安装 **Transporter**
2. 登录开发者账号，拖入 `Flare-Pro-MAS.pkg` 上传
3. 回到 App Store Connect → 该版本 → 选刚上传的构建 → **提交审核**

## 六、和官网 DMG 版的区别

| | 官网 DMG | Mac App Store |
|--|----------|---------------|
| 签名 | Developer ID + 公证 | Apple Distribution |
| 沙盒 | 关闭 | **必须开启** |
| 更新 | 自检 version.json | App Store 更新 |
| 安装 | 拖进应用程序 | App Store 安装 |

两套可同时维护：日常继续 `./Scripts/make_dmg.sh`；上架用 `./Scripts/make_mas.sh`。

## 常见拒审点

1. **没有隐私政策链接** → 官网补一页
2. **屏幕录制用途写不清** → Info.plist 与审核备注写清楚
3. **沙盒外写文件失败** → 已加 Pictures / user-selected 权限；默认存「图片/Flare」
4. **引导去官网下载更新** → MAS 版已禁用官网更新检查

## 需要我继续代劳时

你办完下面任意一项后跟我说一声即可：

1. 已安装 **Apple Distribution** 证书  
2. 已把 `Flare_MacAppStore.provisionprofile` 放进 `Resources/`  
3. 已在 App Store Connect 建好 App  

我可以继续帮你：跑 `make_mas.sh`、检查签名、补隐私政策页、准备审核文案与截图尺寸清单。
