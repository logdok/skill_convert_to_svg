---
name: convert-to-svg
description: Convert raster images (PNG/JPG/JPEG/WebP/BMP/GIF/TIFF) to SVG on macOS using ImageMagick + vtracer, for a single file or a whole folder. Use when the user asks to convert/vectorize/trace an image to SVG, e.g. "сконвертируй картинку в svg", "сделай из png векторный файл 512x512", "vectorize these icons", "png to svg". Canvas size and background handling are always confirmed with the user, never assumed.
---

# convert-to-svg

Pipeline: **vtracer** traces the image at its NATIVE resolution (ImageMagick is only used for optional `--remove-bg` / `--upscale`), then the requested canvas is applied to the SVG itself (`viewBox` + one `<g transform>`).
**Never upscale the raster with Lanczos before tracing**: its negative lobes ring on the alpha edge and vtracer then draws a ragged halo around the outline. Measured on a 256px transparent tiger: tracing the original gave a clean outline, the same trace after a Lanczos upscale gave a fringe. Scaling the vector is lossless, so the output size has no effect on quality.
`--upscale` (Mitchell filter) is an opt-in experiment: it gave more detail on one image (tiger1) but bumpier edges on another (horse2 after `--remove-bg`), so it is not the default.
Everything is plain bash (`scripts/convert.sh`), so it works the same for Claude Code and Codex.

Source of truth: https://github.com/logdok/skill_convert_to_svg.git. Skill folder: `~/.claude/skills/convert-to-svg/` (Claude Code) or `~/.codex/skills/convert-to-svg/` (Codex).
After editing any file here, commit and push to that repo.

## 1. Check / install dependencies (macOS)

```bash
export PATH="$HOME/.cargo/bin:$PATH"
command -v magick  >/dev/null || brew install imagemagick
if ! command -v vtracer >/dev/null; then
  # vtracer-cli from crates.io fails to build (type mismatch), so build from git
  command -v cargo >/dev/null || { brew install rustup && rustup-init -y && source "$HOME/.cargo/env"; }
  cargo install --git https://github.com/visioncortex/vtracer vtracer-cli
  grep -q '.cargo/bin' ~/.zshrc || echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.zshrc
fi
magick -version | head -1 && vtracer --version
```

## 2. Ask the user before running (do NOT assume defaults)

If not stated explicitly in the request, ask:

1. **Canvas size** — `--size WxH` (e.g. `512x512`, `1024x768`; image is fit and centered, so non-square is fine) or `--no-resize` to keep original dimensions. 512x512 is just one example, never a silent default.
2. **Background** — `--keep-background` or `--remove-bg` (make a uniform background transparent; optionally `--fuzz 10%` tolerance, default 5%). **Check the source first** (`magick identify -format '%[channels] %[pixel:p{0,0}]' f.png`): if it is already transparent (`srgba`, corner alpha 0), use `--keep-background`. As a safety net the script itself skips `--remove-bg` (prints `NOTE`) for any file whose four corners are all transparent, because floodfill there only adds a fringe. One stray transparent corner pixel does not count (e.g. an opaque white image with 2 transparent pixels): such a file is flattened onto its background colour first, then floodfilled.
3. **Output location / naming** — default is `<input dir>/output/`; optional `--suffix _512` to get `name_512.svg`.

The script refuses to run without a size choice and a background choice.

## 3. Run

```bash
S=<skill folder>/scripts/convert.sh   # ~/.claude/skills/convert-to-svg (Claude Code) or ~/.codex/skills/convert-to-svg (Codex)

# single file
"$S" path/to/cat.png --size 512x512 --remove-bg --suffix _512

# whole folder (all *.png, *.jpg, *.jpeg, *.webp, *.bmp, *.gif, *.tif, *.tiff, non-recursive)
"$S" path/to/folder/ --size 1024x768 --keep-background -o path/to/out
```

Options: `--fuzz N%`, `--keep-prep`, and trace tuning `--mode spline|polygon|none`, `--simplify 1.5`, `--filter-speckle 4`, `--color-precision 5` (these values are the proven defaults).
With `--remove-bg`, the intermediate `prep_*.png` goes to `<output>/.prep/` and is deleted afterwards unless `--keep-prep`.

Reference command the script is built on:

```bash
vtracer -i in.png -o out.svg --mode spline --simplify 1.5 --filter-speckle 4 --color-precision 5
```
(add `magick in.png -fuzz 5% -fill none -draw "color 0,0 floodfill" -background none prep.png` first only for `--remove-bg`; the script then wraps the result for `--size`).

## 4. Tuning tips

- Ragged/fringed outline → the raster was upscaled with Lanczos (or similar) before tracing (see Pipeline). Trace the original instead.
- Blocky detail on a small source → try `--upscale` and compare; it helps some images and hurts others.
- Too noisy/blobby → raise `--filter-speckle` or `--simplify`, lower `--color-precision`.
- Lost detail → lower `--filter-speckle`/`--simplify`, raise `--color-precision`.
- Gray halo around the outline on an opaque (JPG-like/white-background) source → raise `--fuzz` to ~25%: the anti-aliased light-gray edge pixels are outside the default 5% tolerance, so vtracer traces them as a gray ring. Measured on a 256px horse: 5% left a ring around hooves/tail, 25% removed it and kept the inner lines; heavy `--filter-speckle`/`--color-precision` reduction only blurred detail.
- Background remains → raise `--fuzz`; floodfill starts at the top-left pixel, so it needs a uniform background corner.

## 5. Maintaining this skill

```bash
cd ~/.claude/skills/convert-to-svg && git add -A && git commit -m "..." && git push
```
