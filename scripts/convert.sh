#!/usr/bin/env bash
# Convert raster images (PNG/JPG) to SVG: ImageMagick (prep) -> vtracer (trace).
# Canvas size, background removal and fuzz are NOT defaulted: they must be passed
# explicitly (the agent asks the user first).
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

usage() {
  cat <<'EOF'
Usage: convert.sh <input-file-or-dir> [options]

Canvas (REQUIRED, choose exactly one):
  --size WxH           Resize to fit inside WxH and center on a WxH canvas (e.g. 512x512, 1024x768)
  --no-resize          Keep the original pixel dimensions

Background (REQUIRED, choose exactly one):
  --remove-bg          Flood-fill the background from the top-left pixel to transparent
  --keep-background    Do not touch the background
  --fuzz N%            Tolerance for --remove-bg (default: 5%)

Output:
  -o, --output DIR     Output directory (default: <input dir>/output)
  --suffix STR         Suffix appended to the output name (default: none; e.g. _512)
  --keep-prep          Keep intermediate .prep/ files

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
  echo "Error: background handling not specified. Pass --remove-bg or --keep-background (ask the user)." >&2
  exit 2
fi

command -v magick >/dev/null || { echo "Error: ImageMagick ('magick') not found. See SKILL.md for install steps." >&2; exit 3; }
command -v vtracer >/dev/null || { echo "Error: 'vtracer' not found. See SKILL.md for install steps." >&2; exit 3; }

# Collect input files
files=()
if [[ -d "$INPUT" ]]; then
  base_dir="${INPUT%/}"
  while IFS= read -r -d '' f; do files+=("$f"); done < <(
    find "$base_dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0 | sort -z
  )
else
  base_dir="$(dirname "$INPUT")"
  files=("$INPUT")
fi
[[ ${#files[@]} -gt 0 ]] || { echo "Error: no PNG/JPG files found in $INPUT" >&2; exit 2; }

[[ -n "$OUT" ]] || OUT="$base_dir/output"
PREP="$OUT/.prep"
mkdir -p "$OUT" "$PREP"

ok=0 ; fail=0
for src in "${files[@]}"; do
  name="$(basename "$src")"; name="${name%.*}"
  prep="$PREP/prep_${name}.png"
  dst="$OUT/${name}${SUFFIX}.svg"

  args=("$src")
  [[ "$BG" == "remove" ]] && args+=(-fuzz "$FUZZ" -fill none -draw "color 0,0 floodfill")
  args+=(-background none)
  if [[ -n "$SIZE" ]]; then
    args+=(-filter Lanczos -resize "$SIZE" -gravity center -extent "$SIZE")
  fi

  if magick "${args[@]}" "$prep" \
     && vtracer -i "$prep" -o "$dst" --mode "$MODE" --simplify "$SIMPLIFY" \
          --filter-speckle "$SPECKLE" --color-precision "$PRECISION"; then
    echo "OK   $src -> $dst"; ok=$((ok+1))
  else
    echo "FAIL $src" >&2; fail=$((fail+1))
  fi
done

[[ $KEEP_PREP -eq 1 ]] || rm -rf "$PREP"

echo "Done: $ok converted, $fail failed. Output: $OUT"
[[ $fail -eq 0 ]]
