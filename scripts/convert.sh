#!/usr/bin/env bash
# Convert raster images (PNG, JPG, WebP, BMP, GIF, TIFF) to SVG with vtracer.
# The raster is NEVER resampled: tracing a Lanczos-upscaled copy rings/blurs the alpha edge
# and vtracer draws a ragged halo around the outline. Instead the image is traced at its native
# resolution and the requested canvas is applied to the SVG (viewBox + transform) - lossless.
# Canvas size and background handling are NOT defaulted: they must be passed explicitly
# (the agent asks the user first).
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

usage() {
  cat <<'EOF'
Usage: convert.sh <input-file-or-dir> [options]

Canvas (REQUIRED, choose exactly one):
  --size WxH           Scale the SVG to fit inside WxH and center it on a WxH canvas (e.g. 512x512)
  --no-resize          Keep the original pixel dimensions

Background (REQUIRED, choose exactly one):
  --keep-background    Trace the source as is (right choice for PNGs that are already transparent)
  --remove-bg          Flood-fill a uniform background from the top-left pixel to transparent
                       (skipped automatically for images whose top-left pixel is already transparent)
  --fuzz N%            Tolerance for --remove-bg (default: 5%)

Output:
  -o, --output DIR     Output directory (default: <input dir>/output)
  --suffix STR         Suffix appended to the output name (default: none; e.g. _512)
  --keep-prep          Keep intermediate .prep/ files (only used with --remove-bg)

vtracer tuning (defaults are proven values):
  --mode MODE          spline | polygon | none            (default: spline)
  --simplify N         Corner simplification              (default: 1.5)
  --filter-speckle N   Drop speckles smaller than N px    (default: 4)
  --color-precision N  Color bits per channel             (default: 5)
  -h, --help           Show this help
EOF
}

SIZE="" ; NO_RESIZE=0
BG="" ; FUZZ="5%"
OUT="" ; SUFFIX="" ; KEEP_PREP=0
MODE="spline" ; SIMPLIFY="1.5" ; SPECKLE="4" ; PRECISION="5"
INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --size) SIZE="$2"; shift 2 ;;
    --no-resize) NO_RESIZE=1; shift ;;
    --remove-bg) BG="remove"; shift ;;
    --keep-background) BG="keep"; shift ;;
    --fuzz) FUZZ="$2"; shift 2 ;;
    -o|--output) OUT="$2"; shift 2 ;;
    --suffix) SUFFIX="$2"; shift 2 ;;
    --keep-prep) KEEP_PREP=1; shift ;;
    --mode) MODE="$2"; shift 2 ;;
    --simplify) SIMPLIFY="$2"; shift 2 ;;
    --filter-speckle) SPECKLE="$2"; shift 2 ;;
    --color-precision) PRECISION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) INPUT="$1"; shift ;;
  esac
done

[[ -n "$INPUT" ]] || { echo "Error: input file or folder is required" >&2; usage >&2; exit 2; }
[[ -e "$INPUT" ]] || { echo "Error: not found: $INPUT" >&2; exit 2; }

if [[ -z "$SIZE" && $NO_RESIZE -eq 0 ]]; then
  echo "Error: canvas size not specified. Pass --size WxH or --no-resize (ask the user)." >&2
  exit 2
fi
if [[ -n "$SIZE" && $NO_RESIZE -eq 1 ]]; then
  echo "Error: --size and --no-resize are mutually exclusive" >&2; exit 2
fi
if [[ -n "$SIZE" && ! "$SIZE" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "Error: --size must look like 512x512" >&2; exit 2
fi
if [[ -z "$BG" ]]; then
  echo "Error: background handling not specified. Pass --keep-background or --remove-bg (ask the user)." >&2
  exit 2
fi

command -v vtracer >/dev/null || { echo "Error: 'vtracer' not found. See SKILL.md for install steps." >&2; exit 3; }
if [[ "$BG" == "remove" ]]; then
  command -v magick >/dev/null || { echo "Error: ImageMagick ('magick') not found (needed for --remove-bg). See SKILL.md." >&2; exit 3; }
fi
if [[ -n "$SIZE" ]]; then
  command -v python3 >/dev/null || { echo "Error: python3 is required for --size" >&2; exit 3; }
fi

# Collect input files
files=()
if [[ -d "$INPUT" ]]; then
  base_dir="${INPUT%/}"
  while IFS= read -r -d '' f; do files+=("$f"); done < <(
    find "$base_dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.tif' -o -iname '*.tiff' \) -print0 | sort -z
  )
else
  base_dir="$(dirname "$INPUT")"
  files=("$INPUT")
fi
[[ ${#files[@]} -gt 0 ]] || { echo "Error: no supported images (png, jpg, webp, bmp, gif, tiff) found in $INPUT" >&2; exit 2; }

[[ -n "$OUT" ]] || OUT="$base_dir/output"
PREP="$OUT/.prep"
mkdir -p "$OUT"
[[ "$BG" == "remove" ]] && mkdir -p "$PREP"

# Fit the traced SVG onto a W x H canvas: new header + one <g transform> around the paths
fit_canvas() {
  python3 -I - "$1" "$2" <<'PY'
import re, sys
path, size = sys.argv[1], sys.argv[2]
cw, ch = (int(v) for v in size.split("x"))
s = open(path).read()
m = re.search(r'<svg\b[^>]*\bwidth="(\d+)"[^>]*\bheight="(\d+)"[^>]*>', s)
w, h = int(m.group(1)), int(m.group(2))
k = min(cw / w, ch / h)
tx, ty = (cw - w * k) / 2, (ch - h * k) / 2
head = '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (cw, ch, cw, ch)
body = s[m.end():s.rindex("</svg>")]
if (k, tx, ty) != (1, 0, 0):
    body = '\n<g transform="translate(%.4g %.4g) scale(%.6g)">%s</g>\n' % (tx, ty, k, body)
open(path, "w").write(s[:m.start()] + head + body + "</svg>\n")
PY
}

ok=0 ; fail=0
for src in "${files[@]}"; do
  name="$(basename "$src")"; name="${name%.*}"
  dst="$OUT/${name}${SUFFIX}.svg"

  trace_in="$src"
  if [[ "$BG" == "remove" ]]; then
    # Floodfill on an already-transparent image only adds a ragged fringe: skip it then.
    # All four corners must be transparent (a stray transparent pixel does not count).
    corners_alpha="$(magick "$src[0]" -format '%[fx:p{0,0}.a+p{w-1,0}.a+p{0,h-1}.a+p{w-1,h-1}.a]' info: 2>/dev/null || echo 4)"
    if [[ "$corners_alpha" == "0" ]]; then
      echo "NOTE $src already has a transparent background: --remove-bg skipped" >&2
    else
      # Flatten stray transparent pixels onto the background colour so the floodfill sees one uniform area
      bg_color="$(magick "$src[0]" -format '%[pixel:p{w-1,h-1}]' info:)"
      trace_in="$PREP/prep_${name}.png"
      magick "$src" -background "$bg_color" -alpha remove -alpha off -alpha set \
        -fuzz "$FUZZ" -fill none -draw "color 0,0 floodfill" -background none "$trace_in" \
        || { echo "FAIL $src" >&2; fail=$((fail+1)); continue; }
    fi
  fi

  if vtracer -i "$trace_in" -o "$dst" --mode "$MODE" --simplify "$SIMPLIFY" \
       --filter-speckle "$SPECKLE" --color-precision "$PRECISION" \
     && { [[ -z "$SIZE" ]] || fit_canvas "$dst" "$SIZE"; }; then
    echo "OK   $src -> $dst"; ok=$((ok+1))
  else
    echo "FAIL $src" >&2; fail=$((fail+1))
  fi
done

[[ $KEEP_PREP -eq 1 || "$BG" != "remove" ]] || rm -rf "$PREP"

echo "Done: $ok converted, $fail failed. Output: $OUT"
[[ $fail -eq 0 ]]
