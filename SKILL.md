---
name: convert-to-svg
description: Convert raster images (PNG/JPG/JPEG) to SVG on macOS using ImageMagick + vtracer, for a single file or a whole folder. Use when the user asks to convert/vectorize/trace an image to SVG, e.g. "сконвертируй картинку в svg", "сделай из png векторный файл 512x512", "vectorize these icons", "png to svg". Canvas size and background handling are always confirmed with the user, never assumed.
---

# convert-to-svg

Pipeline: **ImageMagick** prepares the raster (optional background removal, resize/pad to a canvas) → **vtracer** traces it to SVG.
Everything is plain bash (`scripts/convert.sh`), so it works the same for Claude and Codex.

Source of truth: https://github.com/logdok/skill_convert_to_svg.git (local copy: `~/.claude/skills/convert-to-svg/`).
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
2. **Background** — `--remove-bg` (make a uniform background transparent; optionally `--fuzz 10%` tolerance, default 5%), `--keep-background`, or `--source-alpha`. **Check the source first** (`magick identify -format '%[channels]' f.png`, or the corner pixel via `%[pixel:p{0,0}]`): if it is already transparent (`srgba`, corner alpha 0), use `--source-alpha`, NOT `--remove-bg` — floodfill on an already-transparent image leaves a ragged fringe.
3. **Output location / naming** — default is `<input dir>/output/`; optional `--suffix _512` to get `name_512.svg`.

The script refuses to run without a size choice and a background choice.

## 3. Run

```bash
S=~/.claude/skills/convert-to-svg/scripts/convert.sh

# single file
"$S" path/to/cat.png --size 512x512 --remove-bg --suffix _512

# whole folder (all *.png, *.jpg, *.jpeg, non-recursive)
"$S" path/to/folder/ --size 1024x768 --keep-background -o path/to/out
```

Options: `--fuzz N%`, `--keep-prep`, and trace tuning `--mode spline|polygon|none`, `--simplify 1.5`, `--filter-speckle 4`, `--color-precision 5` (these values are the proven defaults).
Intermediate `prep_*.png` files go to `<output>/.prep/` and are deleted afterwards unless `--keep-prep`.

Reference command the script is built on:

```bash
magick in.png -fuzz 5% -fill none -draw "color 0,0 floodfill" -background none \
  -filter Lanczos -resize 512x512 -gravity center -extent 512x512 prep.png \
&& vtracer -i prep.png -o out.svg --mode spline --simplify 1.5 --filter-speckle 4 --color-precision 5
```

## 4. Tuning tips

- `--source-alpha` (transparent PNG): flattens onto white, traces at 2x canvas, then deletes every near-white path (backdrop, gaps between parts, anti-aliasing halo) and sets a `viewBox`. Side effect: genuinely white shapes in the art (e.g. eye whites) are removed too — for such art use `--keep-background` instead.
- Small source (e.g. 256px) → blocky/ragged outline: the 2x supersampling in `--source-alpha` handles it; with other modes upscale via a larger `--size`.

- Too noisy/blobby → raise `--filter-speckle` or `--simplify`, lower `--color-precision`.
- Lost detail → lower `--filter-speckle`/`--simplify`, raise `--color-precision`.
- Background remains → raise `--fuzz`; floodfill starts at the top-left pixel, so it needs a uniform background corner.

## 5. Maintaining this skill

```bash
cd ~/.claude/skills/convert-to-svg && git add -A && git commit -m "..." && git push
```
