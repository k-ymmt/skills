#!/bin/bash
# Screenshot of an iPhone Duo simulator, whichever of its two screens is lit.
#
# Usage: duo-screenshot.sh <UDID> <out.png> [max-pixel-size]
#
# A Duo has two built-in screens — "LCD" (the cover screen, lit while folded) and "LCD-1" (the inner screen, lit
# while open or partially open) — so a plain `simctl io <UDID> screenshot` fails with "Cannot choose between 2
# displays … Invalid argument", and `--display=primary` silently captures the cover screen, which is black while
# the device is open. This captures both, keeps the lit one, and prints what it found:
#
#   posture: closed|open|dark    (open covers "Partially Open" too: the inner screen stays lit)
#   screen: LCD|LCD-1  <width>x<height> px  (<width>x<height> pt)
#   orientation: <UI Orientation as simctl reports it>
#   <out.png>
#
# With max-pixel-size the saved PNG is downsized so a model can read it (points = pixels / 3 only for the
# original size). Exit 1 when the device has no such screens (not a Duo, or not booted).
set -eu

UDID="${1:?UDID of the booted Duo simulator}"
OUT="${2:?output .png}"
MAX="${3:-}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

lit() {  # 0 when the PNG has any pixel that is not (nearly) black
  sips -Z 48 -s format bmp "$1" --out "$WORK/probe.bmp" >/dev/null 2>&1 || return 1
  python3 - "$WORK/probe.bmp" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
offset = int.from_bytes(data[10:14], "little")   # start of the pixel array
step = int.from_bytes(data[28:30], "little") // 8  # 4 with an alpha byte, which is 255 on a black screen too
pixels = data[offset:]
colour = [pixels[i] for i in range(len(pixels)) if step != 4 or i % 4 != 3]
sys.exit(0 if max(colour, default=0) > 24 else 1)
PY
}

for screen in LCD LCD-1; do
  if ! xcrun simctl io "$UDID" screenshot --display="$screen" "$WORK/$screen.png" >"$WORK/$screen.log" 2>&1; then
    echo "error: no screen '$screen' on $UDID (not an iPhone Duo, or not booted):" >&2
    tail -3 "$WORK/$screen.log" >&2
    exit 1
  fi
done

if lit "$WORK/LCD-1.png"; then
  screen=LCD-1; posture=open
elif lit "$WORK/LCD.png"; then
  screen=LCD; posture=closed
else
  screen=LCD; posture=dark   # both black: locked / asleep, or a black app on screen
fi

width=$(sips -g pixelWidth "$WORK/$screen.png" | awk '/pixelWidth/ {print $2}')
height=$(sips -g pixelHeight "$WORK/$screen.png" | awk '/pixelHeight/ {print $2}')
orientation=$(xcrun simctl io "$UDID" enumerate 2>/dev/null | awk -v want="$screen:" '
  /^    \([0-9]+\) / { current = $2 }
  /UI Orientation:/ && current == want { sub(/.*UI Orientation: /, ""); print; exit }')

mkdir -p "$(dirname "$OUT")"
cp "$WORK/$screen.png" "$OUT"
if [ -n "$MAX" ]; then
  sips -Z "$MAX" "$OUT" >/dev/null 2>&1
fi

echo "posture: $posture"
echo "screen: $screen  ${width}x${height} px  ($((width / 3))x$((height / 3)) pt)"
echo "orientation: ${orientation:-unknown}"
echo "$OUT"
