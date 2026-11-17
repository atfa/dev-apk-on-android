#!/usr/bin/env sh
# Smoke test for this skill: scaffold a throwaway project, build it, install it, run its
# acceptance test, remove everything again. Run this after touching any script.
#
#   sh scripts/selfcheck.sh            # setup + build + install + test
#   sh scripts/selfcheck.sh --no-setup # skip setup-toolchain.sh
#   sh scripts/selfcheck.sh --build    # only scaffold + build (works without root)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LIB="$HERE/lib"; [ -f "$LIB/common.sh" ] || LIB="$HERE/../lib"
. "$LIB/common.sh"

MODE=full
case "${1:-}" in
  --no-setup) MODE=no-setup ;;
  --build)    MODE=build ;;
esac

PKG="dev.selfcheck.sample"
WORK="${SELFCHECK_DIR:-${TMPDIR:-$HOME}/dev-apk-selfcheck}"
FAILED=0
cleanup() {
  [ -d "$WORK" ] || return 0
  if have_root && [ "$MODE" = full ]; then
    asroot "pm uninstall '$PKG'" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

check() {   # check <label> <command...>
  label=$1; shift
  if "$@" >"$WORK/.out" 2>&1; then
    say "  PASS  $label"
  else
    say "  FAIL  $label"
    sed 's/^/        /' "$WORK/.out" | tail -15
    FAILED=1
  fi
}

rm -rf "$WORK"; mkdir -p "$WORK"

[ "$MODE" = no-setup ] || [ "$MODE" = build ] || \
  { step "setup-toolchain.sh"; sh "$HERE/setup-toolchain.sh" | sed 's/^/  /' || FAILED=1; }

step "verify-vendor.sh"
check "vendor binaries" sh "$HERE/verify-vendor.sh"

step "new-project.sh"
check "scaffold $PKG" sh "$HERE/new-project.sh" "$WORK/app" "$PKG" "Selfcheck"

step "build.sh"
check "aapt2/javac/d8/apksigner" sh -c "cd '$WORK/app' && ./build.sh"

if [ "$MODE" = build ]; then
  step "done (build only)"
  [ "$FAILED" = 0 ] && say "SELFCHECK PASS" || say "SELFCHECK FAIL"
  exit "$FAILED"
fi

if ! have_root; then
  step "install/test skipped"
  say "  no root - build side passed; install needs one tap, test needs root"
  [ "$FAILED" = 0 ] && say "SELFCHECK PASS (build only)" || say "SELFCHECK FAIL"
  exit "$FAILED"
fi

step "install.sh"
check "pm install + am start" sh -c "cd '$WORK/app' && ./install.sh"

step "probe.sh"
check "app is in the foreground" sh -c "cd '$WORK/app' && ./probe.sh '$PKG' | grep -q 'FOREGROUND: yes'"

step "test.sh"
check "intent + file hooks" sh -c "cd '$WORK/app' && ./test.sh"

step "result"
if [ "$FAILED" = 0 ]; then say "SELFCHECK PASS"; else say "SELFCHECK FAIL"; fi
exit "$FAILED"
