# convert-to-svg

Converts PNG/JPG images to SVG (macOS): ImageMagick prepares the raster, vtracer traces it.
Works as a Claude Skill (`SKILL.md`) and as a plain script for Codex or manual use.

## Manual usage

```bash
scripts/convert.sh <file-or-folder> (--size WxH | --no-resize) (--remove-bg | --keep-background) [options]
```

Examples:

```bash
scripts/convert.sh cat.png --size 512x512 --remove-bg --suffix _512
scripts/convert.sh icons/ --no-resize --keep-background -o icons_svg
scripts/convert.sh --help
```

Size and background handling are required on purpose: nothing is assumed silently.
Dependency install steps are in `SKILL.md`.

Repo: https://github.com/logdok/skill_convert_to_svg.git
