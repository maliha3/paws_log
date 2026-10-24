#!/usr/bin/env bash
# Draws every app icon from tool/make_icon.py.
#
# Each size is drawn at its own resolution rather than resized down from one
# master, so a 20-pixel icon is supersampled from the shape instead of
# squeezed out of a 1024-pixel one — and nothing here can pick up the alpha
# channel iOS rejects.
set -euo pipefail
cd "$(dirname "$0")/.."

draw() { python3 -I tool/make_icon.py "$1" "$2" >/dev/null; }

echo "master"
draw assets/app_icon.png 1024

ios=ios/Runner/Assets.xcassets/AppIcon.appiconset
echo "iOS"
while read -r name px; do
  draw "$ios/$name" "$px"
done <<'SIZES'
Icon-App-1024x1024@1x.png 1024
Icon-App-20x20@1x.png 20
Icon-App-20x20@2x.png 40
Icon-App-20x20@3x.png 60
Icon-App-29x29@1x.png 29
Icon-App-29x29@2x.png 58
Icon-App-29x29@3x.png 87
Icon-App-40x40@1x.png 40
Icon-App-40x40@2x.png 80
Icon-App-40x40@3x.png 120
Icon-App-60x60@2x.png 120
Icon-App-60x60@3x.png 180
Icon-App-76x76@1x.png 76
Icon-App-76x76@2x.png 152
Icon-App-83.5x83.5@2x.png 167
SIZES

echo "Android"
while read -r bucket px; do
  draw "android/app/src/main/res/mipmap-$bucket/ic_launcher.png" "$px"
done <<'SIZES'
mdpi 48
hdpi 72
xhdpi 96
xxhdpi 144
xxxhdpi 192
SIZES

echo "done"
