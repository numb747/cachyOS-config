#!/usr/bin/env bash
# ============================================================================
#  fcitx5 tokyonight 主题素材重建
#
#  主题里的 PNG 全部由同目录的 SVG 渲染而来，不要直接改 PNG——改 SVG 再跑这个。
#  依赖：librsvg（rsvg-convert）。生成预览图还需要 imagemagick。
#
#  用法：
#      ./render.sh            重建 5 张主题素材
#      ./render.sh --preview  额外重建 docs/img/ 下的预览图与字体对比图
# ============================================================================
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$(dirname "$SRC")"

command -v rsvg-convert >/dev/null || { echo "缺 rsvg-convert：sudo pacman -S librsvg" >&2; exit 1; }

# 主题素材。尺寸即 9-patch 的原始像素，theme.conf 里的 Margin 与之配套：
#   panel 40×40 / Margin 12   → 圆角 10px 不会被拉伸
#   highlight 22×22 / Margin 7
for f in panel highlight prev next arrow radio; do
    rsvg-convert -f png -o "$DEST/$f.png" "$SRC/$f.svg"
    printf '  ✓ %s.png\n' "$f"
done

[ "${1:-}" = --preview ] || exit 0

# ── 预览图（纯文档用途，不进系统主题目录）──────────────────────────────────
IMG="$(cd "$DEST/../../../../docs/img" 2>/dev/null && pwd)" || {
    echo "找不到 docs/img/，跳过预览图" >&2; exit 0; }

rsvg-convert -f png -w 1240 -o "$IMG/preview.png" "$SRC/_preview.svg"
printf '  ✓ docs/img/preview.png\n'

command -v magick >/dev/null || { echo "缺 imagemagick，跳过字体对比图" >&2; exit 0; }

# 黑体（现状）vs 思源宋体 的候选框对比
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
sed 's/Sarasa Gothic SC/Sarasa Gothic SC/'   "$SRC/_preview.svg" > "$tmp/a.svg"
sed 's/Sarasa Gothic SC/Noto Serif CJK SC/'  "$SRC/_preview.svg" > "$tmp/b.svg"
rsvg-convert -f png -w 1100 -o "$tmp/a.png" "$tmp/a.svg"
rsvg-convert -f png -w 1100 -o "$tmp/b.png" "$tmp/b.svg"
magick "$tmp/a.png" "$tmp/b.png" -append "$IMG/font-compare.png"
printf '  ✓ docs/img/font-compare.png\n'
