#!/usr/bin/env python3
"""Flare Pro AppIcon — emerald glass + capture frame + flash spark."""

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


def frame_mask(nx: float, ny: float) -> float:
    """Screenshot selection — rounded viewfinder frame."""
    outer = sd_round_box(nx, ny, 0.46, 0.46, 0.12)
    ring = abs(outer) - 0.038
    return smoothstep(0.016, -0.01, ring)


def spark_mask(nx: float, ny: float, scale: float = 1.0) -> float:
    """4-point camera flash, plus a thinner 45° spark."""
    px, py = nx / scale, ny / scale

    def arms(x: float, y: float, reach: float, thick: float) -> float:
        ax, ay = abs(x), abs(y)
        th_h = thick * max(0.1, 1.0 - ax * (1.15 / reach))
        dh = ay - th_h if ax < reach else 1e9
        th_v = thick * max(0.1, 1.0 - ay * (1.15 / reach))
        dv = ax - th_v if ay < reach else 1e9
        return min(dh, dv)

    plus = arms(px, py, 0.50, 0.078)
    s = 0.70710678
    rx = px * s - py * s
    ry = px * s + py * s
    cross = arms(rx, ry, 0.34, 0.036)
    core = sd_circle(px, py, 0.10)
    m = smoothstep(0.016, -0.01, plus)
    m = max(m, smoothstep(0.014, -0.008, cross) * 0.88)
    m = max(m, smoothstep(0.02, -0.01, core))
    glow = smoothstep(0.09, -0.02, plus) * 0.28
    return min(1.0, m + glow)


def mark_mask(nx: float, ny: float) -> float:
    return max(spark_mask(nx, ny), frame_mask(nx, ny) * 0.92)


def iris_mark(nx: float, ny: float) -> tuple[float, float]:
    """Lens iris + diagonal flare. Returns (iris, slash)."""
    ring = abs(math.hypot(nx, ny) - 0.32) - 0.055
    inner = abs(math.hypot(nx, ny) - 0.18) - 0.016
    pupil = sd_circle(nx, ny, 0.038)
    iris = max(smoothstep(0.02, -0.012, min(ring, inner)), smoothstep(0.016, -0.01, pupil) * 0.9)
    blades = 0.0
    for i in range(6):
        ang = i * math.pi / 3 + math.pi / 12
        d = sd_segment(nx, ny, math.cos(ang) * 0.20, math.sin(ang) * 0.20, math.cos(ang) * 0.29, math.sin(ang) * 0.29, 0.016)
        blades = max(blades, smoothstep(0.016, -0.01, d) * 0.7)
    ax, ay, bx, by = -0.58, 0.50, 0.58, -0.50
    abx, aby = bx - ax, by - ay
    ab2 = abx * abx + aby * aby
    t = max(0.0, min(1.0, ((nx - ax) * abx + (ny - ay) * aby) / ab2))
    thick = 0.028 + 0.045 * math.sin(t * math.pi)
    core = sd_segment(nx, ny, ax, ay, bx, by, thick)
    soft = sd_segment(nx, ny, ax, ay, bx, by, thick + 0.045)
    slash = smoothstep(0.018, -0.012, core)
    slash = max(slash, smoothstep(0.035, -0.004, soft) * 0.28)
    slash = max(slash, smoothstep(0.022, -0.01, sd_circle(nx - 0.50, ny + 0.43, 0.055)))
    return max(iris, blades), min(1.0, slash)


def bolt_mask(nx: float, ny: float) -> float:
    """Lightning bolt — clean silhouette at small sizes."""
    d = min(
        sd_segment(nx, ny, -0.06, 0.46, 0.22, 0.08, 0.075),
        sd_segment(nx, ny, 0.22, 0.08, -0.04, 0.08, 0.075),
        sd_segment(nx, ny, -0.04, 0.08, 0.10, -0.48, 0.075),
    )
    return smoothstep(0.018, -0.012, d)


def viewfinder_corners(nx: float, ny: float) -> float:
    arm, thick, inset = 0.22, 0.038, 0.50
    d = 1e9
    for cx, cy, sx, sy in (
        (-inset, inset, 1, -1),
        (inset, inset, -1, -1),
        (-inset, -inset, 1, 1),
        (inset, -inset, -1, 1),
    ):
        d = min(d, sd_box(nx - (cx + sx * arm * 0.5), ny - cy, arm * 0.5, thick))
        d = min(d, sd_box(nx - cx, ny - (cy + sy * arm * 0.5), thick, arm * 0.5))
    return smoothstep(0.016, -0.01, d)


def orbit_mask(nx: float, ny: float) -> float:
    ring = abs(math.hypot(nx, ny) - 0.36) - 0.042
    planet = sd_circle(nx - 0.30, ny + 0.18, 0.10)
    core = sd_circle(nx, ny, 0.075)
    m = smoothstep(0.018, -0.01, ring)
    m = max(m, smoothstep(0.016, -0.01, planet))
    m = max(m, smoothstep(0.016, -0.01, core))
    return m


def paint_bg(style: str, gloss: float, bloom: float, corner: float, vignette: float) -> tuple[float, float, float]:
    if style == "iris":
        return (
            52 + gloss * 36 + bloom * 40 + corner * 28 - vignette * 10,
            22 + gloss * 18 + bloom * 22 + corner * 14 - vignette * 8,
            10 + gloss * 10 + bloom * 8 + corner * 6 - vignette * 6,
        )
    if style == "bolt":
        return (
            10 + gloss * 22 + bloom * 12 + corner * 8 - vignette * 8,
            22 + gloss * 28 + bloom * 40 + corner * 36 - vignette * 10,
            48 + gloss * 36 + bloom * 80 + corner * 70 - vignette * 8,
        )
    if style == "dusk":
        return (
            32 + gloss * 18 + bloom * 40 + corner * 22 - vignette * 8,
            10 + gloss * 12 + bloom * 16 + corner * 10 - vignette * 6,
            58 + gloss * 28 + bloom * 70 + corner * 50 - vignette * 10,
        )
    if style == "coral":
        return (
            58 + gloss * 28 + bloom * 36 + corner * 22 - vignette * 10,
            12 + gloss * 10 + bloom * 12 + corner * 8 - vignette * 6,
            24 + gloss * 14 + bloom * 18 + corner * 12 - vignette * 8,
        )
    return (
        6 + gloss * 14 + bloom * 28 + corner * 10 - vignette * 8,
        36 + gloss * 38 + bloom * 90 + corner * 70 - vignette * 12,
        32 + gloss * 28 + bloom * 70 + corner * 48 - vignette * 10,
    )


def paint_mark(style: str, px: float, py: float, r: float, g: float, b: float) -> tuple[float, float, float]:
    if style == "iris":
        iris, slash = iris_mark(px, py)
        r += iris * (255 - r) * 0.88
        g += iris * (236 - g) * 0.80
        b += iris * (210 - b) * 0.55
        r += slash * (255 - r)
        g += slash * (214 - g) * 0.85
        b += slash * (140 - b) * 0.5
        return r, g, b
    if style == "bolt":
        bolt = bolt_mask(px, py)
        glow = bolt * 0.45
        r += bolt * (255 - r) + glow * 30
        g += bolt * (248 - g) + glow * 24
        b += bolt * (210 - b) + glow * 18
        return r, g, b
    if style == "dusk":
        mark = orbit_mask(px, py)
        glow = mark * 0.4
        r += mark * (255 - r) + glow * 36
        g += mark * (200 - g) + glow * 8
        b += mark * (255 - b) + glow * 28
        return r, g, b
    if style == "coral":
        corners = viewfinder_corners(px, py)
        core = smoothstep(0.02, -0.01, sd_circle(px, py, 0.14))
        mark = max(corners, core)
        glow = core * 0.35
        r += mark * (255 - r) + glow * 20
        g += mark * (230 - g) + glow * 8
        b += mark * (228 - b) + glow * 10
        return r, g, b
    frame = frame_mask(px, py)
    spark = spark_mask(px, py)
    glow = spark * 0.55
    r += frame * (236 - r) * 0.92
    g += frame * (248 - g) * 0.92
    b += frame * (242 - b) * 0.92
    r += spark * (255 - r) + glow * 20
    g += spark * (252 - g) + glow * 28
    b += spark * (230 - b) * 0.55 + glow * 8
    return r, g, b


def render(size: int = 1024, style: str = "spark") -> bytes:
    rgba = bytearray(size * size * 4)
    for y in range(size):
        py = 1.0 - (y + 0.5) / size * 2
        for x in range(size):
            px = (x + 0.5) / size * 2 - 1
            sdf = squircle_sdf(px * 1.012, py * 1.012, n=5.2)
            alpha = 1.0 - smoothstep(-0.030, 0.010, sdf)
            if alpha < 0.002:
                continue
            gloss = smoothstep(-0.15, 1.0, py)
            bloom = math.exp(-(px * px + py * py) * 2.8)
            corner = math.exp(-(math.hypot(px + 0.38, py - 0.42) ** 2) * 2.2)
            vignette = smoothstep(0.2, 1.18, math.hypot(px, py))
            r, g, b = paint_bg(style, gloss, bloom, corner, vignette)
            r, g, b = paint_mark(style, px, py, r, g, b)
            i = (y * size + x) * 4
            rgba[i] = int(max(0, min(255, r)))
            rgba[i + 1] = int(max(0, min(255, g)))
            rgba[i + 2] = int(max(0, min(255, b)))
            rgba[i + 3] = int(max(0, min(255, alpha * 255)))
    return bytes(rgba)


def render_status_template(size: int = 128) -> bytes:
    """Transparent mark for menu-bar template fallback."""
    rgba = bytearray(size * size * 4)
    mark_scale = 0.90
    for y in range(size):
        py = 1.0 - (y + 0.5) / size * 2
        for x in range(size):
            px = (x + 0.5) / size * 2 - 1
            mark = mark_mask(px * mark_scale, py * mark_scale)
            if mark < 0.02:
                continue
            i = (y * size + x) * 4
            rgba[i] = 255
            rgba[i + 1] = 255
            rgba[i + 2] = 255
            rgba[i + 3] = int(min(1.0, mark) * 255)
    return bytes(rgba)


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
    print("==> Rendering Flare Pro icon (capture frame + flash)…")
    write_png(OUT_PNG, 1024, 1024, render(1024, "spark"))
    print(f"    PNG: {OUT_PNG}")
    write_png(OUT_PLAIN, 256, 256, render(256, "spark"))
    for style, name in (
        ("spark", "LogoSpark"),
        ("iris", "LogoIris"),
        ("bolt", "LogoBolt"),
        ("dusk", "LogoDusk"),
        ("coral", "LogoCoral"),
    ):
        path = ROOT / "Resources" / f"{name}.png"
        write_png(path, 512, 512, render(512, style))
        print(f"    Preset {name}: {path}")
    write_png(OUT_STATUS, 128, 128, render_status_template(128))
    print(f"    StatusBar (template): {OUT_STATUS}")
    build_iconset(OUT_PNG)
    print(f"    ICNS: {OUT_ICNS}")
    export_web(OUT_PNG)
    print("Done.")


if __name__ == "__main__":
    main()
