#!/usr/bin/env python3
"""Flare Pro icons — squircle logos tuned for menu-bar + in-app picker."""

from __future__ import annotations

import math
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_ICNS = ROOT / "Resources" / "AppIcon.icns"
OUT_PNG = ROOT / "Resources" / "FlareIcon.png"
OUT_STATUS = ROOT / "Resources" / "StatusBarIcon.png"
OUT_PLAIN = ROOT / "Resources" / "icon.png"
ICONSET = ROOT / "Resources" / "AppIcon.iconset"
DOCS = ROOT / "docs"

# (bg base RGB, mark RGB, accent RGB optional)
STYLES: dict[str, dict[str, tuple[float, float, float] | str]] = {
    "spark": {
        "label": "墨黑闪光",
        "bg": (14, 15, 18),
        "mark": (248, 249, 252),
        "accent": (255, 255, 255),
    },
    "iris": {
        "label": "琥珀镜头",
        "bg": (24, 18, 10),
        "mark": (255, 196, 92),
        "accent": (255, 224, 160),
    },
    "bolt": {
        "label": "电光快拍",
        "bg": (8, 18, 36),
        "mark": (120, 196, 255),
        "accent": (210, 236, 255),
    },
    "dusk": {
        "label": "录制红点",
        "bg": (28, 10, 12),
        "mark": (255, 92, 88),
        "accent": (255, 170, 160),
    },
    "coral": {
        "label": "长截滚页",
        "bg": (14, 14, 16),
        "mark": (236, 236, 240),
        "accent": (180, 180, 186),
    },
}


def _crc(chunk_type: bytes, data: bytes) -> int:
    return zlib.crc32(chunk_type + data) & 0xFFFFFFFF


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", _crc(tag, data))

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * stride : (y + 1) * stride])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def smoothstep(a: float, b: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - a) / (b - a + 1e-9)))
    return t * t * (3 - 2 * t)


def squircle_sdf(nx: float, ny: float, n: float = 5.2) -> float:
    return (abs(nx) ** n + abs(ny) ** n) ** (1.0 / n) - 1.0


def sd_box(px: float, py: float, hx: float, hy: float) -> float:
    dx = abs(px) - hx
    dy = abs(py) - hy
    return math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0)


def sd_segment(px, py, ax, ay, bx, by, thick) -> float:
    abx, aby = bx - ax, by - ay
    apx, apy = px - ax, py - ay
    ab2 = abx * abx + aby * aby or 1e-6
    t = max(0.0, min(1.0, (apx * abx + apy * aby) / ab2))
    cx, cy = ax + abx * t, ay + aby * t
    return math.hypot(px - cx, py - cy) - thick


def sd_circle(px: float, py: float, r: float) -> float:
    return math.hypot(px, py) - r


def sd_ring(px: float, py: float, r: float, w: float) -> float:
    return abs(math.hypot(px, py) - r) - w


def sd_round_box(px: float, py: float, hx: float, hy: float, rad: float) -> float:
    ax = abs(px) - hx + rad
    ay = abs(py) - hy + rad
    return math.hypot(max(ax, 0.0), max(ay, 0.0)) + min(max(ax, ay), 0.0) - rad


def frame_mask(nx: float, ny: float, thick: float = 0.09) -> float:
    # 外框贴边：几乎占满 squircle
    outer = sd_round_box(nx, ny, 0.88, 0.88, 0.22)
    ring = abs(outer) - thick
    return smoothstep(0.014, -0.010, ring)


def cover(sdf: float, aa: float = 0.012) -> float:
    return smoothstep(aa, -aa, sdf)


def spark_arm(px: float, py: float, reach: float, thick: float) -> float:
    """沿 X 轴的尖臂：根部厚、尖端收成针，不再平头截断。"""
    ax, ay = abs(px), abs(py)
    t = ax / max(reach, 1e-6)
    if t >= 1.0:
        return math.hypot(ax - reach, ay)
    half = thick * (1.0 - t) ** 1.12
    return ay - half


def spark_mask(nx: float, ny: float, aa: float = 0.012) -> float:
    """四角星芒：十字四臂，尖端收细，尽量铺满图标。"""
    plus = min(spark_arm(nx, ny, 0.82, 0.155), spark_arm(ny, nx, 0.82, 0.155))
    core = sd_circle(nx, ny, 0.09)
    return cover(min(plus, core), aa)


def iris_mark(nx: float, ny: float) -> float:
    ring = abs(math.hypot(nx, ny) - 0.58) - 0.085
    inner = abs(math.hypot(nx, ny) - 0.34) - 0.028
    pupil = sd_circle(nx, ny, 0.10)
    m = smoothstep(0.02, -0.012, min(ring, inner))
    m = max(m, smoothstep(0.018, -0.012, pupil))
    for i in range(6):
        ang = i * math.pi / 3 + math.pi / 12
        d = sd_segment(
            nx, ny,
            math.cos(ang) * 0.28, math.sin(ang) * 0.28,
            math.cos(ang) * 0.52, math.sin(ang) * 0.52,
            0.028,
        )
        m = max(m, smoothstep(0.016, -0.01, d) * 0.8)
    return m


def bolt_mask(nx: float, ny: float) -> float:
    d = min(
        sd_segment(nx, ny, -0.06, 0.70, 0.34, 0.08, 0.12),
        sd_segment(nx, ny, 0.34, 0.08, -0.04, 0.08, 0.12),
        sd_segment(nx, ny, -0.04, 0.08, 0.18, -0.72, 0.12),
    )
    return smoothstep(0.020, -0.014, d)


def record_mark(nx: float, ny: float) -> float:
    arm, thick, inset = 0.28, 0.058, 0.62
    d = 1e9
    for cx, cy, sx, sy in (
        (-inset, inset, 1, -1),
        (inset, inset, -1, -1),
        (-inset, -inset, 1, 1),
        (inset, -inset, -1, 1),
    ):
        d = min(d, sd_box(nx - (cx + sx * arm * 0.5), ny - cy, arm * 0.5, thick))
        d = min(d, sd_box(nx - cx, ny - (cy + sy * arm * 0.5), thick, arm * 0.5))
    corners = smoothstep(0.018, -0.012, d)
    dot = smoothstep(0.022, -0.012, sd_circle(nx, ny, 0.22))
    inner = smoothstep(0.018, -0.012, sd_circle(nx, ny, 0.09))
    return max(corners, dot - inner * 0.35)


def scroll_mark(nx: float, ny: float) -> float:
    # 黑白：竖向文档页 + 双侧滚动刻度，铺满画布
    page = abs(sd_round_box(nx, ny + 0.02, 0.46, 0.68, 0.08)) - 0.055
    m = smoothstep(0.018, -0.012, page)
    for yy in (-0.28, -0.04, 0.20):
        line = abs(sd_round_box(nx, ny - yy, 0.28, 0.028, 0.01)) - 0.012
        m = max(m, smoothstep(0.016, -0.01, line) * 0.85)
    rail = abs(sd_round_box(nx - 0.30, ny + 0.02, 0.048, 0.52, 0.014)) - 0.014
    thumb = abs(sd_round_box(nx - 0.30, ny + 0.16, 0.038, 0.18, 0.012)) - 0.012
    m = max(m, smoothstep(0.016, -0.01, rail) * 0.7)
    m = max(m, smoothstep(0.016, -0.01, thumb))
    chev = min(
        sd_segment(nx, ny - 0.72, 0.0, 0.0, -0.12, -0.09, 0.042),
        sd_segment(nx, ny - 0.72, 0.0, 0.0, 0.12, -0.09, 0.042),
    )
    m = max(m, smoothstep(0.018, -0.012, chev))
    return m


def style_mask(style: str, nx: float, ny: float) -> float:
    if style == "spark":
        return spark_mask(nx, ny)
    if style == "iris":
        return iris_mark(nx, ny)
    if style == "bolt":
        return bolt_mask(nx, ny)
    if style == "dusk":
        return record_mark(nx, ny)
    if style == "coral":
        return scroll_mark(nx, ny)
    return spark_mask(nx, ny)


def mix_bg(style: str, gloss: float, vignette: float) -> tuple[float, float, float]:
    spec = STYLES[style]
    br, bg, bb = spec["bg"]  # type: ignore[misc]
    lift = gloss * 18 - vignette * 8
    edge = vignette * 5
    return (
        max(0, min(255, br + lift - edge)),
        max(0, min(255, bg + lift * 0.88 - edge)),
        max(0, min(255, bb + lift * 0.78 - edge * 0.7)),
    )


def paint_mark_rgb(style: str, strength: float) -> tuple[float, float, float]:
    spec = STYLES[style]
    mr, mg, mb = spec["mark"]  # type: ignore[misc]
    ar, ag, ab = spec["accent"]  # type: ignore[misc]
    t = max(0.0, min(1.0, strength))
    glow = t * t * 0.35
    return (
        mr * t + ar * glow + glow * 18,
        mg * t + ag * glow + glow * 18,
        mb * t + ab * glow + glow * 18,
    )


def downsample_box(src: bytes, src_size: int, factor: int) -> bytes:
    dst = src_size // factor
    out = bytearray(dst * dst * 4)
    n = factor * factor
    for y in range(dst):
        for x in range(dst):
            r = g = b = a = 0
            for oy in range(factor):
                for ox in range(factor):
                    i = ((y * factor + oy) * src_size + (x * factor + ox)) * 4
                    r += src[i]
                    g += src[i + 1]
                    b += src[i + 2]
                    a += src[i + 3]
            j = (y * dst + x) * 4
            out[j] = r // n
            out[j + 1] = g // n
            out[j + 2] = b // n
            out[j + 3] = a // n
    return bytes(out)


def render_pixels(size: int, style: str) -> bytes:
    rgba = bytearray(size * size * 4)
    aa = 2.2 / size
    edge_aa = 2.4 / size
    for y in range(size):
        py = 1.0 - (y + 0.5) / size * 2
        for x in range(size):
            px = (x + 0.5) / size * 2 - 1
            sdf = squircle_sdf(px * 1.008, py * 1.008, n=5.4)
            alpha = 1.0 - smoothstep(-edge_aa, edge_aa, sdf)
            if alpha < 0.002:
                continue

            gloss = smoothstep(-0.08, 0.96, py)
            vignette = smoothstep(0.28, 1.18, math.hypot(px, py))
            r, g, b = mix_bg(style, gloss, vignette)
            rim = smoothstep(0.016, 0.0, abs(sdf + 0.010)) * (0.40 + gloss * 0.35)
            r += rim * 14
            g += rim * 14
            b += rim * 16

            if style == "spark":
                spark = spark_mask(px, py, aa)
                bloom = spark_mask(px, py, aa * 6.0) * 0.18
                sr, sg, sb = paint_mark_rgb(style, spark)
                sheen = max(0.0, 1.0 - math.hypot(px + 0.16, py - 0.22) * 1.8) * spark
                r = r + (sr - r) * spark + bloom * 28 + sheen * 18
                g = g + (sg - g) * spark + bloom * 28 + sheen * 18
                b = b + (sb - b) * spark + bloom * 32 + sheen * 22
            else:
                mark = style_mask(style, px, py)
                mr, mg, mb = paint_mark_rgb(style, mark)
                r = r + (mr - r) * mark
                g = g + (mg - g) * mark
                b = b + (mb - b) * mark

            i = (y * size + x) * 4
            rgba[i] = int(max(0, min(255, r)))
            rgba[i + 1] = int(max(0, min(255, g)))
            rgba[i + 2] = int(max(0, min(255, b)))
            rgba[i + 3] = int(max(0, min(255, alpha * 255)))
    return bytes(rgba)


def render(size: int = 1024, style: str = "spark", ssaa: int = 1) -> bytes:
    factor = 2 if ssaa >= 2 else 1
    pixels = render_pixels(size * factor, style)
    if factor == 1:
        return pixels
    return downsample_box(pixels, size * factor, factor)


def render_status_template(size: int = 128) -> bytes:
    """Black squircle + white mark — menu-bar fallback."""
    return render(size, "spark")


def icon_name(base: int, retina: bool) -> str:
    return f"icon_{base}x{base}@2x.png" if retina else f"icon_{base}x{base}.png"


def build_iconset(master: Path) -> None:
    work = Path(tempfile.mkdtemp(prefix="flareicon_"))
    iconset = work / "AppIcon.iconset"
    iconset.mkdir()
    clean = work / "master.png"
    subprocess.run(["sips", "-s", "format", "png", str(master), "--out", str(clean)], check=True, capture_output=True)

    sizes = [
        (16, icon_name(16, False)),
        (32, icon_name(16, True)),
        (32, icon_name(32, False)),
        (64, icon_name(32, True)),
        (128, icon_name(128, False)),
        (256, icon_name(128, True)),
        (256, icon_name(256, False)),
        (512, icon_name(256, True)),
        (512, icon_name(512, False)),
        (1024, icon_name(512, True)),
    ]
    tmp = work / "tmp.png"
    for px, name in sizes:
        subprocess.run(["sips", "-z", str(px), str(px), str(clean), "--out", str(tmp)], check=True, capture_output=True)
        shutil.copy2(tmp, iconset / name)

    icns = work / "AppIcon.icns"
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    shutil.copytree(iconset, ICONSET)
    shutil.copy2(icns, OUT_ICNS)
    shutil.rmtree(work, ignore_errors=True)


def export_web(master: Path) -> None:
    if not DOCS.exists():
        return
    subprocess.run(["sips", "-z", "256", "256", str(master), "--out", str(DOCS / "logo.png")], check=True, capture_output=True)
    subprocess.run(["sips", "-z", "32", "32", str(master), "--out", str(DOCS / "favicon-32.png")], check=True, capture_output=True)
    subprocess.run(["sips", "-z", "180", "180", str(master), "--out", str(DOCS / "apple-touch-icon.png")], check=True, capture_output=True)
    ico = DOCS / "favicon.ico"
    subprocess.run(["sips", "-s", "format", "ico", "-z", "32", "32", str(master), "--out", str(ico)], check=False, capture_output=True)


def main() -> None:
    print("==> Rendering Flare Pro logos (menu-bar tuned squircles)…")
    write_png(OUT_PNG, 1024, 1024, render(1024, "spark", ssaa=2))
    print(f"    PNG: {OUT_PNG}")
    write_png(OUT_PLAIN, 256, 256, render(256, "spark", ssaa=2))
    for style, name in (
        ("spark", "LogoSpark"),
        ("iris", "LogoIris"),
        ("bolt", "LogoBolt"),
        ("dusk", "LogoDusk"),
        ("coral", "LogoCoral"),
    ):
        path = ROOT / "Resources" / f"{name}.png"
        write_png(path, 1024, 1024, render(1024, style, ssaa=2 if style == "spark" else 1))
        print(f"    Preset {name} ({STYLES[style]['label']}): {path}")
    write_png(OUT_STATUS, 256, 256, render(256, "spark", ssaa=2))
    print(f"    StatusBar: {OUT_STATUS}")
    build_iconset(OUT_PNG)
    print(f"    ICNS: {OUT_ICNS}")
    export_web(OUT_PNG)
    print("Done.")


if __name__ == "__main__":
    main()
