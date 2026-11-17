#!/usr/bin/env sh
# Screenshot -> ASCII art, so a text-only model can "see" the screen.
#   usage: screen.sh [width-in-columns]     default 70
# Root is needed for `screencap`; without it the script says so and stops.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/lib"; [ -f "$LIB/common.sh" ] || LIB="$HERE/../lib"
. "$LIB/common.sh"
[ -n "$PY" ] || die "python3 needed for ascii.py"
W="${1:-70}"
STAGE="$ANDROID_STAGE_DIR/screen.png"
LOCAL="${TMPDIR:-$HOME/.cache}/screen.png"
mkdir -p "$(dirname "$LOCAL")"

if have_root; then
  # /data/local/tmp, then copy: the screenshot has to be readable by whoever reads it
  asroot "screencap -p '$STAGE' && chmod 644 '$STAGE'" || die "screencap failed"
  cp "$STAGE" "$LOCAL"
elif ! screencap -p "$LOCAL" >/dev/null 2>&1; then
  die "screencap needs root on this device"
fi
"$PY" "$HERE/ascii.py" "$LOCAL" "$W"
