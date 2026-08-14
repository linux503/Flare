#!/usr/bin/env python3
"""Flare Pro AppIcon — distinctive lens iris + flare slash + viewfinder, no white rim."""

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
ICONSET = ROOT / "Resources" / "AppIcon.iconset"


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


def viewfinder_mask(nx: float, ny: float) -> float:
    """Four corner L-brackets — screenshot DNA, more prominent."""
    arm = 0.24
    thick = 0.045
    inset = 0.52
    corners = [
        (-inset, inset, 1, -1),
        (inset, inset, -1, -1),
        (-inset, -inset, 1, 1),
        (inset, -inset, -1, 1),
    ]
    d = 1e9
    for cx, cy, sx, sy in corners:
        d = min(d, sd_box(nx - (cx + sx * arm * 0.5), ny - cy, arm * 0.5, thick))
        d = min(d, sd_box(nx - cx, ny - (cy + sy * arm * 0.5), thick, arm * 0.5))
    return smoothstep(0.018, -0.012, d)


def iris_mask(nx: float, ny: float) -> float:
    """Bold camera iris ring — core identity mark."""
    ring = sd_ring(nx, ny, 0.32, 0.055)
    inner = sd_ring(nx, ny, 0.18, 0.018)
    pupil = sd_circle(nx, ny, 0.038)
    d = min(ring, inner)
    m = smoothstep(0.02, -0.012, d)
    m = max(m, smoothstep(0.018, -0.01, pupil) * 0.9)
    return m


def aperture_blades(nx: float, ny: float) -> float:
    """Hex aperture ticks — reads as lens, not a ban symbol."""
    d = 1e9
    for i in range(6):
        ang = i * math.pi / 3 + math.pi / 12
        ax = math.cos(ang) * 0.20
        ay = math.sin(ang) * 0.20
        bx = math.cos(ang) * 0.29
        by = math.sin(ang) * 0.29
        d = min(d, sd_segment(nx, ny, ax, ay, bx, by, 0.018))
    return smoothstep(0.016, -0.01, d) * 0.7


def flare_slash_mask(nx: float, ny: float) -> float:
    """
    Signature diagonal lens-flare slash — unique silhouette.
    Tapers: thicker center, sharp tip spark (no “hilt” blob).
    """
    ax, ay = -0.58, 0.50
    bx, by = 0.58, -0.50
    # Distance along slash for taper
    abx, aby = bx - ax, by - ay
    ab2 = abx * abx + aby * aby
    t = ((nx - ax) * abx + (ny - ay) * aby) / ab2
    t = max(0.0, min(1.0, t))
    # Thickness peaks mid-beam, thin at ends
    thick = 0.028 + 0.045 * math.sin(t * math.pi)
    core = sd_segment(nx, ny, ax, ay, bx, by, thick)
    soft = sd_segment(nx, ny, ax, ay, bx, by, thick + 0.045)

    # Bright tip spark (lower-right) — round flare node
    tip = sd_circle(nx - 0.50, ny + 0.43, 0.055)
    # Upper-left soft origin glow
    origin = sd_circle(nx + 0.48, ny - 0.40, 0.035)

    m = smoothstep(0.018, -0.012, core)
    m = max(m, smoothstep(0.035, -0.004, soft) * 0.28)
    m = max(m, smoothstep(0.022, -0.01, tip))
    m = max(m, smoothstep(0.02, -0.008, origin) * 0.75)
    return min(1.0, m)


def render(size: int = 1024) -> bytes:
    rgba = bytearray(size * size * 4)
    for y in range(size):
        py = 1.0 - (y + 0.5) / size * 2
        for x in range(size):
            px = (x + 0.5) / size * 2 - 1
            sdf = squircle_sdf(px * 1.012, py * 1.012, n=5.2)
            alpha = 1.0 - smoothstep(-0.030, 0.010, sdf)
            if alpha < 0.002:
                continue

            # Deep cinematic glass — cool charcoal, subtle top light
            gloss = smoothstep(0.10, 0.95, py) * 0.18
            sheen = math.exp(-((px * 0.7 + py * 0.45 - 0.08) ** 2) * 9) * 0.14
            depth = smoothstep(0.05, -1.0, py) * 0.12
            # slight cool tint in body via channel split later
            base = 12 + gloss * 190 + sheen * 150 - depth * 28
            base = max(5, min(40, base))

            iris = iris_mask(px, py)
            blades = aperture_blades(px, py)
            slash = flare_slash_mask(px, py)
            corners = viewfinder_mask(px, py)

            # Slash cuts across iris — dominate identity
            mark = max(slash, iris * 0.95, blades * 0.75, blades)
            glow = slash * 0.40 + iris * 0.12

            # Near-white mark with cool edge; body stays dark
            r = base + mark * (235 - base) + glow * 40
            g = base + mark * (238 - base) + glow * 42
            b = base + 2 + mark * (245 - base) + glow * 48

            i = (y * size + x) * 4
            rgba[i] = int(max(0, min(255, r)))
            rgba[i + 1] = int(max(0, min(255, g)))
            rgba[i + 2] = int(max(0, min(255, b)))
            rgba[i + 3] = int(max(0, min(255, alpha * 255)))
    return bytes(rgba)


def render_status_template(size: int = 128) -> bytes:
    """Transparent mark for menu-bar template tinting (light/dark menu bars)."""
    rgba = bytearray(size * size * 4)
    # 0.86：图形更大、留白更少，菜单栏里更易辨认
    mark_scale = 0.86
    for y in range(size):
        py = 1.0 - (y + 0.5) / size * 2
        for x in range(size):
            px = (x + 0.5) / size * 2 - 1
            nx, ny = px * mark_scale, py * mark_scale
            iris = iris_mask(nx, ny)
            blades = aperture_blades(nx, ny)
            slash = flare_slash_mask(nx, ny)
            corners = viewfinder_mask(nx, ny)
            mark = max(slash, iris * 0.95, blades * 0.75, corners)
            if mark < 0.02:
                continue
            a = min(1.0, mark)
            i = (y * size + x) * 4
            rgba[i] = 255
            rgba[i + 1] = 255
            rgba[i + 2] = 255
            rgba[i + 3] = int(a * 255)
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


def main() -> None:
    print("==> Rendering Flare Pro icon (iris + flare slash)…")
    write_png(OUT_PNG, 1024, 1024, render(1024))
    print(f"    PNG: {OUT_PNG}")
    write_png(OUT_STATUS, 128, 128, render_status_template(128))
    print(f"    StatusBar (template): {OUT_STATUS}")
    build_iconset(OUT_PNG)
    print(f"    ICNS: {OUT_ICNS}")
    print("Done.")


if __name__ == "__main__":
    main()
