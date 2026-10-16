---
name: convert-to-svg
description: Convert raster images (PNG/JPG/JPEG/WebP/BMP/GIF/TIFF) to SVG on macOS using ImageMagick + vtracer, for a single file or a whole folder. Use when the user asks to convert/vectorize/trace an image to SVG, e.g. "сконвертируй картинку в svg", "сделай из png векторный файл 512x512", "vectorize these icons", "png to svg". Canvas size and background handling are always confirmed with the user, never assumed.
---

# convert-to-svg

Pipeline: optional background removal → optional flat-color cleanup → **vtracer** at NATIVE resolution → requested SVG canvas (`viewBox` + one `<g transform>`). ImageMagick decodes/encodes preparation files; the flat-color helper uses only Python's standard library.
**Never upscale the raster to meet the SVG canvas size.** Trace the source at native resolution, then fit the vector into the requested canvas. Raster enlargement can create fringes and cannot add genuine source detail. The script does not offer a raster-upscale option.
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

Options: `--fuzz N%`, `--keep-prep`, and trace tuning `--mode spline|polygon|none`, `--simplify 1.5`, `--filter-speckle 4`, `--color-precision 5` (these values are the standard defaults). Use `--flat-palette` below when a flat illustration develops gray/color fragments along its outlines.
Intermediate preparation files go to `<output>/.prep/` and are deleted afterwards unless `--keep-prep`.

Reference command the script is built on:

```bash
vtracer -i in.png -o out.svg --mode spline --simplify 1.5 --filter-speckle 4 --color-precision 5
```
(add `magick in.png -fuzz 5% -fill none -draw "color 0,0 floodfill" -background none prep.png` first only for `--remove-bg`; the script then wraps the result for `--size`).

## 4. Clean flat icons without increasing SVG size

For **opaque flat fills with strong outlines**, gray patches on heads/clothes and colored seams often come from tracing antialias shades as separate regions. Increasing trace precision preserves that noise. Clean the raster's palette **before** tracing; recoloring finished paths cannot fix their fragmented geometry.

1. Reuse already-confirmed canvas/background choices for improvements of the same image.
2. Inspect the actual source composited on white and a contrasting background. Transparent pixels can contain hidden RGB; a thumbnail that ignores alpha may show a different shape. Do not redraw that hidden color as visible geometry.
3. Pick the artwork's intended solid colors from opaque interiors (including black outlines, white or gray fills if present). Do not use a screenshot of an already faulty trace. Start with the smallest palette that preserves the meaningful colors, not an arbitrary maximum color count.
4. Run the opt-in `--flat-palette` mode. It snaps near-neutral edge shades to neutral palette entries, maps other pixels to the nearest palette color, thresholds alpha, then traces with color precision 8. Source dimensions and aspect ratio stay unchanged.

```bash
"$S" icon.png --no-resize --keep-background \
  --flat-palette '#000000,#E4BC96,#009245,#4E9DC4,#3E489D,#8F0000' \
  --simplify 0.8 --filter-speckle 4 -o clean_svg
```

The six colors above are **an example**, not a universal icon palette. `--flat-neutral 20` is the default RGB channel-spread threshold (0 disables neutral protection); `--flat-alpha 128` is the default opacity cutoff (1–255). The helper is `scripts/prepare_flat.py`; no Pillow or OpenCV installation is needed. Cleanup keeps the source's native dimensions.

Compare the rendered SVG at intended size and 2–4× with the source: outer contour, holes, eyes, fingers, thin strokes, colors, and transparency. Start with speckle 4; lower it for small meaningful details. Raise it only when the removed islands are confirmed artifacts. Do not compensate with aggressive simplification that distorts hands or faces. Keep the original file until the improved version is reviewed. Check bytes and path count as well as appearance; never embed the raster to fake fidelity.

Measured example (266×336, two figures, six flat colors): native cleanup with neutral 20, alpha 128, simplify 0.8 and speckle 12 removed gray fragments. The delivered SVG shrank from 15,841 to 4,122 bytes (74%). Speckle 12 was appropriate for that faceless illustration; it can erase eyes in other icons. This is a tested example, not a guaranteed compression ratio. For photographs, gradients, semitransparent artwork or intentionally nuanced shading, keep the normal pipeline instead.

## 5. Small raster → large SVG canvas (e.g. 262×206 → 512×512)

Use `--size 512x512`. The script traces the original resolution, then changes only the SVG root and one parent transform. Background/palette preparation may change pixel colors, but must keep the native dimensions. A larger requested canvas never enlarges the raster.

```bash
"$S" small.png --size 512x512 --remove-bg -o output
# Add --flat-palette and tuned trace options if the flat artwork needs cleanup.
```

Preserve aspect ratio with `k = min(canvas_width/source_width, canvas_height/source_height)` and center with `tx = (canvas_width-source_width*k)/2`, `ty = (canvas_height-source_height*k)/2`. For 262×206 on 512×512: scale ≈ 1.95419847328, visible source bounds ≈ 512×402.565, top/bottom margins ≈ 54.718. These margins are expected; do not stretch to a square or crop the artwork to remove them.

Verify the invariant by converting once with `--no-resize` and once with `--size 512x512`, keeping the same other options. Path data, colors and path count must match exactly; only the root dimensions/viewBox and wrapper transform change. The regression test also checks preparation images remain native-sized and the source bytes are unchanged. A tested food illustration kept all 27 paths identical; canvas scaling added less than 100 bytes to an approximately 8.7 KB SVG.

Render the final SVG at 512×512 for inspection, but do not use that preview as a tracing input. Explain the distinction: **vector scaling introduces no additional raster blur; raster-to-vector tracing is an approximation and cannot restore detail absent from the small source**. Avoid promising perfect source recovery. Preserve native fine details with restrained speckle/simplification settings rather than upscaling as an automatic fix.

## 6. Tuning tips

- Ragged/fringed outline → check whether the input itself was previously enlarged; trace the original if available.
- Blocky detail on a small source → obtain a sharper source or simplify the intended icon design; a larger SVG canvas cannot restore missing detail.
- Too noisy/blobby → raise `--filter-speckle` or `--simplify`, lower `--color-precision`.
- Lost detail → lower `--filter-speckle`/`--simplify`, raise `--color-precision`.
- Gray halo around the outline on an opaque (JPG-like/white-background) source → raise `--fuzz` to ~25%: the anti-aliased light-gray edge pixels are outside the default 5% tolerance, so vtracer traces them as a gray ring. Measured on a 256px horse: 5% left a ring around hooves/tail, 25% removed it and kept the inner lines; heavy `--filter-speckle`/`--color-precision` reduction only blurred detail.
- Gray or colored fragments inside otherwise flat outlines → use the pre-trace `--flat-palette` cleanup above. Merely mapping colors on existing SVG paths retains bad boundaries.
- Background remains → raise `--fuzz`; floodfill starts at the top-left pixel, so it needs a uniform background corner.

## 7. Maintaining this skill

Validate script changes with `python3 scripts/test_flat.py` (requires ImageMagick and vtracer).

```bash
cd ~/.claude/skills/convert-to-svg && git add -A && git commit -m "..." && git push
```
