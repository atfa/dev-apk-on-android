#!/usr/bin/env sh
# Acceptance test template: clean install -> drive the app through its hooks -> assert on the
# app's own log file. Replace the two checks with real behaviour once the app does something.
#
#   ./test.sh              full run
#   ./test.sh --keep       do not uninstall afterwards
#
# The app must write files/testlog.txt (templates/src/**/MainActivity.java shows how).
# Needs root: without it everything builds and installs, but nothing can be observed.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/lib"; [ -f "$LIB/common.sh" ] || LIB="$HERE/../lib"
. "$LIB/common.sh"
load_app_env "$HERE"
APK=$(readlink -f "$APK_NAME")

[ -f "$APK" ] || die "no apk: $APK (run ./build.sh)"
if ! have_root; then
  say "SKIP: test.sh cannot observe the app without root."
  say "      build + install still work: ./build.sh && ./install.sh (one tap)"
  exit 3
fi

TLOG_DIR="/data/data/$APP_PACKAGE/files"
TLOG="$TLOG_DIR/testlog.txt"

# The app's directory is only the real one in the *global* mount namespace: on some su setups a
# plain `su -c` sees a shadow /data/data and anything written there never reaches the app.
# Reads and writes of app data therefore go through asroot_global (see lib/root.sh).
readlog() { asroot_global "cat '$TLOG' 2>/dev/null" 2>/dev/null || true; }

waitfor() {   # waitfor <extended-regex> <seconds-if-present>
  n=0
  while [ "$n" -lt "${2:-20}" ]; do
    if readlog | grep -Eq "$1"; then return 0; fi
    sleep 1
    n=$((n + 1))
  done
  return 1
}

fail() {
  say "--- app log ---"; readlog | tail -20 | sed 's/^/  /'
  sh "$HERE/probe.sh" "$APP_PACKAGE" | sed 's/^/  /' || true
  die "$1"
}

step "clean install"
asroot "pm uninstall '$APP_PACKAGE'" >/dev/null 2>&1 || true
asroot "pm install -g '$APK'" >/dev/null || die "pm install failed"
asroot "input keyevent KEYCODE_WAKEUP" >/dev/null 2>&1 || true
asroot "svc power stayon true" >/dev/null 2>&1 || true   # a sleeping screen stops the app
asroot "input keyevent KEYCODE_HOME" >/dev/null 2>&1 || true
sleep 1

step "hook via intent extra"
asroot "am start -n '$ACTIVITY' --es hook ping" >/dev/null
waitfor 'hook: ping' 20 || fail "intent hook never arrived (see the skill: references/testing.md)"

step "hook via file (Android 14+ drops extras when the app is already on top)"
asroot_global "echo 'hook=fromfile' > '$TLOG_DIR/testhook' && chmod 644 '$TLOG_DIR/testhook'" \
  || die "cannot write the hook file (needs root in the global mount namespace)"
asroot "am force-stop '$APP_PACKAGE'" >/dev/null 2>&1 || true
sleep 1
asroot "am start -n '$ACTIVITY'" >/dev/null
waitfor 'hook: hook=fromfile' 20 || fail "file hook never arrived"

step "still alive"
sh "$HERE/probe.sh" "$APP_PACKAGE" | sed 's/^/  /'

[ "${1:-}" = "--keep" ] || asroot "pm uninstall '$APP_PACKAGE'" >/dev/null 2>&1 || true
say ""
say "PASS"
