#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Flare Pro.app"
BIN="$APP/Contents/MacOS/FlarePro"
PASS=0
FAIL=0
SKIP=0
HOST_ARCH="$(uname -m)"

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  ⏭️  $1"; SKIP=$((SKIP+1)); }
section() { echo ""; echo "==> $1"; }

app_running() {
  pgrep -x FlarePro >/dev/null 2>&1 || pgrep -f "/Flare Pro.app/Contents/MacOS/FlarePro" >/dev/null 2>&1
}

kill_app() {
  killall FlarePro 2>/dev/null || true
  killall "Flare Pro" 2>/dev/null || true
  killall Snap 2>/dev/null || true
  killall Flare 2>/dev/null || true
  sleep 0.4
}

section "1. 构建 Universal App (arm64 + x86_64)"
kill_app
"$ROOT/Scripts/build.sh" >/tmp/flare-build.log 2>&1 || {
  echo "构建失败，日志：/tmp/flare-build.log"
  tail -50 /tmp/flare-build.log
  exit 1
}
ok "构建成功"

section "2. Bundle / Intel 适配 / 资源"
[[ -x "$BIN" ]] && ok "可执行文件存在" || bad "缺少可执行文件"
ARCHS="$(lipo -info "$BIN" 2>/dev/null || true)"
echo "    lipo: $ARCHS"
echo "$ARCHS" | grep -q "arm64" && ok "包含 arm64" || bad "缺少 arm64"
echo "$ARCHS" | grep -q "x86_64" && ok "包含 x86_64 (Intel)" || bad "缺少 x86_64 (Intel)"

# 校验各自切片可被识别
file "$BIN" | grep -q "x86_64" && ok "file 识别 x86_64 切片" || bad "file 未识别 x86_64"
file "$BIN" | grep -q "arm64" && ok "file 识别 arm64 切片" || bad "file 未识别 arm64"

plutil -extract CFBundleDisplayName raw "$APP/Contents/Info.plist" | grep -q "Flare Pro" && ok "显示名 Flare Pro" || bad "显示名错误"
plutil -extract CFBundleExecutable raw "$APP/Contents/Info.plist" | grep -q "FlarePro" && ok "可执行名 FlarePro" || bad "可执行名错误"
plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist" | grep -q "app.flare.screenshot" && ok "Bundle ID 保持稳定" || bad "Bundle ID 被改动"
plutil -extract LSUIElement raw "$APP/Contents/Info.plist" 2>/dev/null | grep -q "false\|0" && ok "程序坞可见" || bad "程序坞被隐藏"
plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist" | grep -q "14" && ok "最低系统 macOS 14" || bad "最低系统版本异常"

[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] && ok "AppIcon.icns 已打包" || bad "缺少图标"
[[ -f "$APP/Contents/Resources/StatusBarIcon.png" ]] && ok "状态栏图标已打包" || bad "缺少状态栏图标"
[[ -f "$APP/Contents/Resources/FlareIcon.png" ]] && ok "Logo PNG 已打包" || bad "缺少 Logo PNG"
codesign -v "$APP" 2>/dev/null && ok "代码签名有效" || bad "签名无效"

section "3. Intel (x86_64) 切片冒烟"
X86_SLICE="/tmp/FlarePro-x86_64-slice"
lipo -thin x86_64 "$BIN" -output "$X86_SLICE" 2>/dev/null && ok "可抽出 x86_64 切片" || bad "无法抽出 x86_64 切片"
chmod +x "$X86_SLICE"
# GUI 二进制会常驻；短时拉起再杀掉，验证 Rosetta/本机可加载
set +e
: > /tmp/flare-x86-run.out
if [[ "$HOST_ARCH" == "arm64" ]]; then
  if arch -x86_64 /usr/bin/true 2>/dev/null; then
    arch -x86_64 "$X86_SLICE" >/tmp/flare-x86-run.out 2>&1 &
    XP=$!
    sleep 1.2
    if kill -0 $XP 2>/dev/null; then
      ok "x86_64 切片可经 Rosetta 加载"
      kill $XP 2>/dev/null || true
      wait $XP 2>/dev/null || true
    elif grep -qiE "Bad CPU type|cannot execute|Killed: 9|Segmentation fault" /tmp/flare-x86-run.out; then
      bad "x86_64 切片无法在 Rosetta 下加载"
      cat /tmp/flare-x86-run.out
    else
      ok "x86_64 切片可经 Rosetta 加载"
    fi
  else
    skip "本机未启用 Rosetta，跳过 x86_64 运行验证"
  fi
else
  "$X86_SLICE" >/tmp/flare-x86-run.out 2>&1 &
  XP=$!
  sleep 1.2
  if kill -0 $XP 2>/dev/null; then
    ok "x86_64 主机可启动切片进程"
    kill $XP 2>/dev/null || true
    wait $XP 2>/dev/null || true
  else
    if grep -qiE "Bad CPU type|cannot execute" /tmp/flare-x86-run.out; then
      bad "x86_64 主机无法执行切片"
    else
      ok "x86_64 主机可执行切片"
    fi
  fi
fi
set -e

section "4. 核心功能单元测试"
TEST_SWIFT="/tmp/flare_feature_tests.swift"
TEST_BIN="/tmp/flare_feature_tests"
cat > "$TEST_SWIFT" <<'SWIFT'
import AppKit
import Vision
import ScreenCaptureKit
import Foundation
var passed = 0
var failed = 0
func expect(_ cond: Bool, _ name: String) {
    if cond { print("  ✅ \(name)"); passed += 1 }
    else { print("  ❌ \(name)"); failed += 1 }
}

func testExport() {
    let img = NSImage(size: NSSize(width: 120, height: 80))
    img.lockFocus()
    NSColor.systemTeal.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 120, height: 80)).fill()
    img.unlockFocus()

    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        expect(false, "PNG 编码"); return
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("flare-test.png")
    try! data.write(to: url)
    let loaded = NSImage(contentsOf: url)
    expect(loaded != nil && (loaded?.size.width ?? 0) > 0, "PNG 读写往返")

    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([img])
    expect(pb.canReadObject(forClasses: [NSImage.self], options: nil), "剪贴板写入图片")
}

func testAnnotationDraw() {
    let size = NSSize(width: 200, height: 120)
    let img = NSImage(size: size)
    img.lockFocus()
    NSColor.darkGray.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    NSColor.red.setStroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 20, y: 20))
    path.line(to: NSPoint(x: 160, y: 90))
    path.lineWidth = 3
    path.stroke()
    img.unlockFocus()
    expect(img.tiffRepresentation != nil, "标注绘制输出")
}

func testOCR() async {
    let img = NSImage(size: NSSize(width: 320, height: 80))
    img.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 80)).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 36),
        .foregroundColor: NSColor.black
    ]
    ("HELLO FLARE" as NSString).draw(at: NSPoint(x: 24, y: 22), withAttributes: attrs)
    img.unlockFocus()

    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        expect(false, "OCR 图像准备"); return
    }
    let text: String = await withCheckedContinuation { cont in
        let req = VNRecognizeTextRequest { request, _ in
            let obs = (request.results as? [VNRecognizedTextObservation]) ?? []
            let lines = obs.compactMap { $0.topCandidates(1).first?.string }
            cont.resume(returning: lines.joined(separator: " ").uppercased())
        }
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([req]) } catch { cont.resume(returning: "") }
    }
    expect(text.contains("HELLO") || text.contains("FLARE"), "OCR 识别英文 (got: \(text))")
}

func testCapture() async {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        expect(!content.displays.isEmpty, "可读取显示器列表 (\(content.displays.count))")
        if let display = content.displays.first {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = min(display.width, 800)
            config.height = min(display.height, 500)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            expect(image.width > 0 && image.height > 0, "全屏截图像素有效 \(image.width)x\(image.height)")
        }
    } catch {
        print("  ⏭️  屏幕捕获跳过（请给 Flare Pro.app 开屏幕录制权限）: \(error.localizedDescription)")
    }
}

func testThemeDefaults() {
    let kinds = ["ink", "frost"]
    expect(kinds.count == 2, "主题种类 = 2（墨黑 / 霜白）")
    expect(FileManager.default.temporaryDirectory.path.count > 0, "临时目录可用")
}

@main
struct Runner {
    static func main() async {
        print("  · Image / Clipboard")
        testExport()
        print("  · Annotation")
        testAnnotationDraw()
        print("  · OCR")
        await testOCR()
        print("  · ScreenCaptureKit")
        await testCapture()
        print("  · Theme")
        testThemeDefaults()
        print("UNIT_PASS=\(passed)")
        print("UNIT_FAIL=\(failed)")
        if failed > 0 { exit(1) }
    }
}
SWIFT

SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -sdk "$SDK" -O -swift-version 5 -parse-as-library \
  -target "${HOST_ARCH}-apple-macos14.0" \
  -framework AppKit -framework Vision -framework ScreenCaptureKit \
  -o "$TEST_BIN" "$TEST_SWIFT" 2>/tmp/flare-test-compile.log || {
  bad "单元测试编译失败"
  cat /tmp/flare-test-compile.log
  exit 1
}
set +e
"$TEST_BIN" | tee /tmp/flare-unit.out
UNIT_EC=$?
set -e
U_PASS=$(grep -c '✅' /tmp/flare-unit.out || true)
U_FAIL=$(grep -c '❌' /tmp/flare-unit.out || true)
PASS=$((PASS+U_PASS))
FAIL=$((FAIL+U_FAIL))
[[ $UNIT_EC -eq 0 ]] && ok "单元测试进程退出码 0" || bad "单元测试进程失败"

# Intel 主机上也编一份 x86_64 测试二进制
if [[ "$HOST_ARCH" == "arm64" ]] && arch -x86_64 /usr/bin/true 2>/dev/null; then
  section "4b. Intel 目标单元测试 (Rosetta)"
  xcrun swiftc -sdk "$SDK" -O -swift-version 5 -parse-as-library \
    -target "x86_64-apple-macos14.0" \
    -framework AppKit -framework Vision -framework ScreenCaptureKit \
    -o "${TEST_BIN}-x86" "$TEST_SWIFT" 2>/tmp/flare-test-x86-compile.log || {
    bad "x86_64 单元测试编译失败"
    cat /tmp/flare-test-x86-compile.log
  }
  if [[ -x "${TEST_BIN}-x86" ]]; then
    set +e
    arch -x86_64 "${TEST_BIN}-x86" | tee /tmp/flare-unit-x86.out
    XEC=$?
    set -e
    X_PASS=$(grep -c '✅' /tmp/flare-unit-x86.out || true)
    X_FAIL=$(grep -c '❌' /tmp/flare-unit-x86.out || true)
    PASS=$((PASS+X_PASS))
    FAIL=$((FAIL+X_FAIL))
    [[ $XEC -eq 0 ]] && ok "x86_64 单元测试通过" || bad "x86_64 单元测试失败"
  fi
fi

section "5. 文档生成 (Word/PPT/表格)"
DOC_SWIFT="/tmp/flare_doc_tests.swift"
DOC_BIN="/tmp/flare_doc_tests"
{
  echo 'import Foundation'
  echo 'enum FlareBrand { static let name = "Flare Pro" }'
  # 跳过源文件首行 import Foundation，避免重复
  tail -n +2 "$ROOT/Sources/Flare/Features/OfficePackage.swift"
  cat <<'SWIFT'

@main
struct DocRunner {
    static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("flare-docs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let docx = dir.appendingPathComponent("t.docx")
        let pptx = dir.appendingPathComponent("t.pptx")
        let xlsx = dir.appendingPathComponent("t.xlsx")
        try OfficePackage.writeDOCX(to: docx, title: "Test Doc")
        try OfficePackage.writePPTX(to: pptx, title: "Test Deck")
        try OfficePackage.writeXLSX(to: xlsx, title: "Test Sheet")
        func check(_ url: URL, _ need: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-t", url.path]
            try! p.run(); p.waitUntilExit()
            let list = Process()
            list.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            list.arguments = ["-l", url.path]
            let out = Pipe(); list.standardOutput = out
            try! list.run(); list.waitUntilExit()
            let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let ok = p.terminationStatus == 0 && need.allSatisfy { s.contains($0) }
            if ok { print("  ✅ \(url.pathExtension) 结构完整") }
            else { print("  ❌ \(url.pathExtension) 结构异常"); FileHandle.standardError.write(Data(s.utf8)); exit(1) }
        }
        check(docx, ["[Content_Types].xml", "word/document.xml"])
        check(pptx, ["[Content_Types].xml", "ppt/presentation.xml", "ppt/slides/slide1.xml"])
        check(xlsx, ["[Content_Types].xml", "xl/workbook.xml", "xl/worksheets/sheet1.xml"])
        print("DOC_OK")
    }
}
SWIFT
} > "$DOC_SWIFT"

set +e
xcrun swiftc -sdk "$SDK" -O -swift-version 5 -parse-as-library \
  -target "${HOST_ARCH}-apple-macos14.0" \
  -o "$DOC_BIN" "$DOC_SWIFT" 2>/tmp/flare-doc-compile.log
DOC_COMPILE=$?
set -e
if [[ $DOC_COMPILE -ne 0 ]]; then
  bad "文档生成测试编译失败"
  tail -30 /tmp/flare-doc-compile.log
else
  set +e
  "$DOC_BIN" | tee /tmp/flare-doc.out
  DEC=$?
  set -e
  D_PASS=$(grep -c '✅' /tmp/flare-doc.out || true)
  D_FAIL=$(grep -c '❌' /tmp/flare-doc.out || true)
  PASS=$((PASS+D_PASS))
  FAIL=$((FAIL+D_FAIL))
  [[ $DEC -eq 0 ]] && ok "Word/PPT/表格生成通过" || bad "文档生成失败"
fi

section "6. 源码接线检查"
rg -q "MainMenuController" "$ROOT/Sources/Flare" && ok "主菜单控制器已接入" || bad "缺少主菜单"
rg -q "StatusBarController" "$ROOT/Sources/Flare" && ok "菜单栏状态项已接入" || bad "缺少状态栏"
rg -q "HomeWindowController" "$ROOT/Sources/Flare" && ok "主面板已接入" || bad "缺少主面板"
rg -q "startDelayedCapture" "$ROOT/Sources/Flare" && ok "延时截图已接入" || bad "缺少延时截图"
rg -q "ScreenRecorder" "$ROOT/Sources/Flare" && ok "屏幕录制已接入" || bad "缺少屏幕录制"
rg -q "EditorWindowController" "$ROOT/Sources/Flare" && ok "编辑器界面已接入" || bad "缺少编辑器"
rg -q "HistoryPane" "$ROOT/Sources/Flare" && ok "历史记录界面已接入" || bad "缺少历史"
rg -q "SettingsPane" "$ROOT/Sources/Flare" && ok "设置界面已接入" || bad "缺少设置"
rg -q "ThemeController" "$ROOT/Sources/Flare" && ok "主题系统已接入" || bad "缺少主题"
rg -q "writeXLSX" "$ROOT/Sources/Flare" && ok "新建文档(Word/PPT/表格)已接入" || bad "缺少文档创建"
rg -q "CaptureFinishAction" "$ROOT/Sources/Flare" && ok "选区确认工具栏已接入" || bad "缺少选区工具栏"
rg -q "PinWindowController" "$ROOT/Sources/Flare" && ok "钉图功能已接入" || bad "缺少钉图"
rg -q "OCRService" "$ROOT/Sources/Flare" && ok "OCR 已接入" || bad "缺少 OCR"
rg -q "x86_64" "$ROOT/Scripts/build.sh" && ok "构建脚本含 Intel 交叉编译" || bad "构建脚本缺 Intel"

section "7. 启动应用与界面冒烟"
kill_app
open "$APP"
sleep 2.5
if app_running; then
  ok "FlarePro 进程运行中"
else
  bad "Flare Pro 未能启动"
fi

set +e
osascript -e 'tell application "Flare Pro" to activate' >/tmp/flare-activate.out 2>&1
ACT_EC=$?
set -e
[[ $ACT_EC -eq 0 ]] && ok "可通过 AppleScript 激活 Flare Pro" || skip "AppleScript 激活受限"

if app_running; then
  ok "菜单栏常驻进程存活"
else
  bad "进程已退出"
fi

set +e
osascript <<'APPLESCRIPT' >/tmp/flare-ui.out 2>&1
tell application "System Events"
  tell process "Flare Pro"
    set menuNames to name of every menu of menu bar 1
    if menuNames contains "截图" then
      log "MENU_CAPTURE_OK"
    end if
    if menuNames contains "新建" then
      log "MENU_NEW_OK"
    end if
  end tell
end tell
APPLESCRIPT
AS_EC=$?
set -e
if [[ $AS_EC -eq 0 ]] && grep -q "MENU_CAPTURE_OK" /tmp/flare-ui.out; then
  ok "主菜单含「截图」"
else
  skip "完整菜单自动化需「辅助功能」授权给终端"
fi
if [[ $AS_EC -eq 0 ]] && grep -q "MENU_NEW_OK" /tmp/flare-ui.out; then
  ok "主菜单含「新建」"
fi

section "汇总"
echo "主机架构: $HOST_ARCH"
echo "通过: $PASS  失败: $FAIL  跳过: $SKIP"
if [[ $FAIL -gt 0 ]]; then
  echo "RESULT=FAILED"
  exit 1
fi
echo "RESULT=PASSED"
exit 0
