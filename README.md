<h1 align="center">convert-to-svg</h1>

<p align="center">
  <b>Turn PNG / JPG / WebP icons into clean, scalable SVG — in one command.</b><br>
  A <a href="https://docs.claude.com/en/docs/claude-code/skills">Claude Code skill</a> that is also a plain bash script.
</p>

<p align="center">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg">
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Powered by vtracer" src="https://img.shields.io/badge/powered%20by-vtracer-orange.svg">
</p>

---

## Why this exists

Tracing a small raster icon with [vtracer](https://github.com/visioncortex/vtracer) usually works great — until you "prepare" the image first. The obvious pipeline (upscale to the target size, remove the background, then trace) produces a **ragged, dashed halo around the outline**:

- upscaling with Lanczos rings and blurs the edge of the alpha channel, and the tracer faithfully draws that blur;
- flood-filling the background of an image that is *already transparent* only adds more fringe.

`convert-to-svg` avoids both:

| Step | Naive pipeline | convert-to-svg |
| --- | --- | --- |
| Trace | on a resampled copy | on the **original pixels** |
| Output size | resize the raster, then trace | trace, then fit the **vector** to the canvas (`viewBox` + one transform) — lossless |
| Background | always flood-fill | skipped automatically when the image is **already transparent** |

The result is the same outline you get from running `vtracer` by hand on the original file — plus a canvas of any size, centered.

## Features

- **Any canvas size, centered** — `--size 512x512`, `--size 1024x768`, or keep the original with `--no-resize`. Scaling happens in the SVG, so quality never depends on the output size.
- **Smart background handling** — make a uniform background transparent (`--remove-bg`), or leave it alone (`--keep-background`). Already-transparent images are detected (all four corners) and never flood-filled.
- **Single file or whole folder** — PNG, JPG/JPEG, WebP, BMP, GIF and TIFF.
- **Explicit by design** — canvas size and background handling are *required*. The script refuses to guess, and the Claude skill asks you instead of assuming.
- **Tunable tracing** — expose vtracer's `--simplify`, `--filter-speckle`, `--color-precision` and `--mode`.
- **Plain bash** — no wrapper framework. Works from Claude Code, Codex, or your terminal.

## Requirements

- macOS (developed and tested here; the script is plain bash and may work on Linux, but that is untested)
- [vtracer](https://github.com/visioncortex/vtracer) CLI
- `python3` (only used when `--size` is given)
- [ImageMagick](https://imagemagick.org) (only used for `--remove-bg`)

```bash
brew install imagemagick

# vtracer: the crates.io release of vtracer-cli failed to build for us, so install from git
brew install rustup && rustup-init -y && source "$HOME/.cargo/env"
cargo install --git https://github.com/visioncortex/vtracer vtracer-cli
```

## Install as a Claude Code skill

```bash
git clone https://github.com/logdok/skill_convert_to_svg.git ~/.claude/skills/convert-to-svg
```

Then just ask Claude in plain language:

> "Convert `icons/` to SVG, 512×512, transparent background"
> "Vectorize `logo.png`"
> "сконвертируй `cat.png` в svg"

Claude checks your dependencies, looks at whether the source is already transparent, asks about anything you did not specify (canvas size, background, output folder) and runs the script.

## Use it as a plain script

```bash
scripts/convert.sh <file-or-folder> (--size WxH | --no-resize) (--remove-bg | --keep-background) [options]
```

```bash
# one file, 512×512 canvas, transparent background, saved as cat_512.svg
scripts/convert.sh cat.png --size 512x512 --remove-bg --suffix _512

# a whole folder, original size, keep the background as is
scripts/convert.sh icons/ --no-resize --keep-background -o icons_svg

# non-square canvas — the image is fit and centered
scripts/convert.sh logo.png --size 1024x768 --keep-background
```

### Options

| Option | Description |
| --- | --- |
| `--size WxH` | Fit the SVG inside a `W×H` canvas and center it |
| `--no-resize` | Keep the original pixel dimensions |
| `--keep-background` | Trace the source as is (right for already-transparent images) |
| `--remove-bg` | Flood-fill a uniform background from the top-left pixel to transparent. Skipped automatically if all four corners are already transparent |
| `--fuzz N%` | Tolerance for `--remove-bg` (default `5%`) |
| `-o, --output DIR` | Output folder (default `<input dir>/output`) |
| `--suffix STR` | Append a suffix to the file name, e.g. `_512` → `name_512.svg` |
| `--keep-prep` | Keep intermediate files (only used with `--remove-bg`) |
| `--mode` | `spline` (default), `polygon` or `none` |
| `--simplify N` | Corner simplification (default `1.5`) |
| `--filter-speckle N` | Drop speckles smaller than `N` px (default `4`) |
| `--color-precision N` | Color bits per channel (default `5`) |

## Tuning tips

- **Ragged or fringed outline** → something resampled the raster before tracing. Trace the original.
- **Gray ring around the outline on an opaque (white-background) image** → raise `--fuzz` to about `25%`. The anti-aliased light-gray edge pixels fall outside the default `5%` tolerance, so they get traced as a ring.
- **Noisy or blobby result** → raise `--filter-speckle` or `--simplify`, lower `--color-precision`.
- **Lost detail** → lower `--filter-speckle` / `--simplify`, raise `--color-precision`.
- **Background remains** → raise `--fuzz`. The flood-fill starts at the top-left pixel, so the background needs a uniform corner.
- **Small source image** → no problem: the vector scales losslessly. A larger original still gives the tracer more pixels to work with.

## How it works

```
source ──► (optional) flood-fill background ──► vtracer (native resolution) ──► fit to canvas ──► .svg
              only for --remove-bg                spline, no resampling          viewBox + transform
```

`--size` rewrites the SVG header to `width`/`height`/`viewBox` of the canvas and wraps the paths in a single `<g transform="translate(…) scale(…)">`. With `--no-resize` the tracer output is left untouched.

## Credits

- [vtracer](https://github.com/visioncortex/vtracer) by VisionCortex does the actual tracing.
- [ImageMagick](https://imagemagick.org) handles the optional background removal.

## License

[MIT](LICENSE)
