#!/usr/bin/env sh
# Install the apk on this device and start it.
#   ./install.sh [apk]        root: silent pm install + am start   no root: one tap
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/lib"; [ -f "$LIB/common.sh" ] || LIB="$HERE/../lib"
. "$LIB/common.sh"
load_app_env "$HERE"

APK=$(readlink -f "${1:-$HERE/${APK_NAME:-app.apk}}")
[ -f "$APK" ] || die "no apk: $APK (run ./build.sh first)"

if ! have_root; then
  say "no root: opening the system installer - tap Install, then start the app"
  termux-open "$APK"
  say "installed manually: $APP_PACKAGE"
  say "tip: only root can drive/verify the app from a script (see references/testing.md)"
  exit 0
fi

# system_server is what opens the apk for `pm install` - it cannot read /data/data/com.termux,
# so the file has to be staged somewhere world-readable first.
STAGE="$ANDROID_STAGE_DIR/$APP_PACKAGE.apk"
asroot "cp '$APK' '$STAGE' && chmod 644 '$STAGE'"

# Guard against a verifier dialog that never returns (see silent-install.sh).
TMO=
if asroot "timeout 1 true" >/dev/null 2>&1; then TMO="timeout 300 "; fi

if ! asroot "${TMO}pm install -r -g '$STAGE'"; then
  # OEM package verifiers (Play Protect on One UI, etc.) turn pm install into a dialog that
  # blocks forever, even as root. Turn verification off and retry once.
  warn "install failed - disabling the package verifier and retrying"
  sh "$HERE/silent-install.sh" >/dev/null 2>&1 || true
  asroot "${TMO}pm install -r -g '$STAGE'" || die "install failed: $STAGE"
fi

asroot "am force-stop '$APP_PACKAGE'" >/dev/null 2>&1 || true
# Android 14+ refuses activity starts from a background shell: make the launcher the
# foreground task first, then start.
asroot "input keyevent KEYCODE_HOME" >/dev/null 2>&1 || true
sleep 1
asroot "am start -n '$ACTIVITY'" || die "am start failed: $ACTIVITY"
say "installed + started: $ACTIVITY"
