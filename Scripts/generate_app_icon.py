#!/usr/bin/env python3
"""Generate the Gift Vault app icon master PNG (1024x1024, opaque RGB)."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
BACKGROUND_TOP = (62, 39, 91)
BACKGROUND_BOTTOM = (32, 20, 48)
BOX = (196, 148, 64)
RIBBON = (244, 226, 178)
LID = (172, 126, 50)


def render_icon(size: int = SIZE) -> Image.Image:
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)

    for y in range(size):
        t = y / (size - 1)
        row = tuple(
            int(BACKGROUND_TOP[i] + (BACKGROUND_BOTTOM[i] - BACKGROUND_TOP[i]) * t)
            for i in range(3)
        )
        draw.line([(0, y), (size, y)], fill=row)

    scale = size / 1024.0

    def s(v: float) -> float:
        return v * scale

    draw.rounded_rectangle(
        (s(232), s(420), s(792), s(836)), radius=s(40), fill=BOX
    )
    draw.rounded_rectangle(
        (s(200), s(348), s(824), s(452)), radius=s(36), fill=LID
    )

    ribbon_w = s(72)
    center_x = s(512)
    draw.rectangle(
        (center_x - ribbon_w / 2, s(348), center_x + ribbon_w / 2, s(836)),
        fill=RIBBON,
    )

    loop_w, loop_h = s(190), s(150)
    bow_y = s(206)
    draw.ellipse(
        (center_x - loop_w - s(12), bow_y, center_x - s(12), bow_y + loop_h),
        outline=RIBBON,
        width=int(s(46)),
    )
    draw.ellipse(
        (center_x + s(12), bow_y, center_x + loop_w + s(12), bow_y + loop_h),
        outline=RIBBON,
        width=int(s(46)),
    )
    draw.ellipse((center_x - s(52), s(300), center_x + s(52), s(404)), fill=RIBBON)

    return img


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"),
    )
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    render_icon().save(args.output, format="PNG", optimize=True)
    print(f"Wrote {args.output} ({SIZE}x{SIZE}, opaque RGB)")


if __name__ == "__main__":
    main()
