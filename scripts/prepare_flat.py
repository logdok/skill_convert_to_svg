#!/usr/bin/env python3
"""Remove antialias color fragments before tracing opaque, flat-color artwork.

Uses ImageMagick for decoding/encoding; Python itself needs no third-party modules.
This deliberately thresholds alpha and is not intended for translucent artwork.
"""

import argparse
import re
import subprocess
from pathlib import Path


def palette_argument(value):
    colors = value.split(",")
    if not 2 <= len(colors) <= 32:
        raise argparse.ArgumentTypeError("palette must contain 2–32 comma-separated #RRGGBB colors")
    result = []
    for color in colors:
        color = color.strip()
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
            raise argparse.ArgumentTypeError(f"invalid palette color: {color!r}; use #RRGGBB")
        result.append(tuple(int(color[i:i + 2], 16) for i in (1, 3, 5)))
    result = tuple(dict.fromkeys(result))
    if len(result) < 2:
        raise argparse.ArgumentTypeError("palette must contain at least two distinct colors")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--palette", required=True, type=palette_argument)
    parser.add_argument("--neutral-threshold", type=int, default=20)
    parser.add_argument("--alpha-threshold", type=int, default=128)
    args = parser.parse_args()
    if not 0 <= args.neutral_threshold <= 255:
        parser.error("--neutral-threshold must be between 0 and 255")
    if not 1 <= args.alpha_threshold <= 255:
        parser.error("--alpha-threshold must be between 1 and 255")
    if args.source.resolve() == args.output.resolve():
        parser.error("source and output must differ")

    # Use the same decoded first frame for both dimensions and pixels.
    frame = str(args.source.resolve()) + "[0]"
    width, height = map(int, subprocess.check_output(
        ["magick", "identify", "-format", "%w %h", frame], text=True
    ).split())
    raw = subprocess.check_output(["magick", frame, "-colorspace", "sRGB", "-depth", "8", "rgba:-"])
    if len(raw) != width * height * 4:
        raise RuntimeError("unexpected decoded pixel count")

    neutral = tuple(c for c in args.palette if max(c) - min(c) <= args.neutral_threshold)
    cache = {}
    out = bytearray(len(raw))
    for offset in range(0, len(raw), 4):
        r, g, b, alpha = raw[offset:offset + 4]
        if alpha < args.alpha_threshold:
            continue  # Hidden RGB must never turn into visible geometry.
        rgb = (r, g, b)
        if rgb not in cache:
            choices = args.palette
            if args.neutral_threshold and neutral and max(rgb) - min(rgb) < args.neutral_threshold:
                choices = neutral
            color = min(choices, key=lambda c: sum((x - y) ** 2 for x, y in zip(c, rgb)))
            cache[rgb] = bytes((*color, 255))
        out[offset:offset + 4] = cache[rgb]

    subprocess.run([
        "magick", "-size", f"{width}x{height}", "-depth", "8", "rgba:-", str(args.output.resolve())
    ], input=out, check=True)


if __name__ == "__main__":
    main()
