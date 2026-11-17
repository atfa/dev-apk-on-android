#!/usr/bin/env bash
# Build, package and sign an APK on the phone: aapt2 -> javac -> d8(R8) -> zip -> apksigner.
# Config: ./app.env next to this script (created by new-project.sh).
#   ./build.sh                    (bash - never "sh build.sh")
#   R8_JAR=~/r8-full.jar ./build.sh   use a different dexer
set -euo pipefail
cd "$(dirname "$0")"
# app.env first: it decides PLATFORM_API, which is what $ANDROID_JAR is derived from.
[ -f app.env ] || { echo "ERROR: no app.env here (run new-project.sh)" >&2; exit 1; }
. ./app.env
LIB="$PWD/lib"; [ -f "$LIB/common.sh" ] || LIB="$PWD/../lib"
. "$LIB/common.sh"
load_app_env "$PWD"

OUT=out
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex" "$OUT/apk"

need aapt2 aapt2
[ -f "$ANDROID_JAR" ] || die "missing $ANDROID_JAR - run scripts/setup-toolchain.sh"

echo "==> aapt2 compile (resources)"
LINK_RES=
if [ -d res ] && [ -n "$(ls -A res 2>/dev/null)" ]; then
  aapt2 compile --dir res -o "$OUT/res.zip"
  LINK_RES=$OUT/res.zip
fi

echo "==> aapt2 link (binary manifest + R.java, API $PLATFORM_API, min $MIN_API)"
# The manifest carries no <uses-sdk>: the api levels are passed here, so app.env is the
# single source of truth and the two cannot drift apart.
aapt2 link -o "$OUT/apk/base.apk" -I "$ANDROID_JAR" --manifest AndroidManifest.xml \
  --min-sdk-version "$MIN_API" --target-sdk-version "$PLATFORM_API" \
  --auto-add-overlay --java "$OUT/gen" $LINK_RES

echo "==> javac"
find src "$OUT/gen" -name '*.java' > "$OUT/sources.txt"
[ -s "$OUT/sources.txt" ] || die "no .java files under src/"
javac -nowarn -Xlint:-options -source 8 -target 8 \
  -bootclasspath "$ANDROID_JAR" -classpath "$ANDROID_JAR" \
  -d "$OUT/classes" "@$OUT/sources.txt"
find "$OUT/classes" -name '*.class' -print -quit | grep -q . || die "javac produced no classes"

echo "==> d8 (.class -> classes.dex)"
# Termux's own `d8` is R8 3.3 and dies on JDK-11+ NestMembers (anonymous classes).
if [ -f "$R8_JAR" ]; then
  DEXER=(java -cp "$R8_JAR" com.android.tools.r8.D8)
elif command -v d8 >/dev/null 2>&1; then
  DEXER=(d8); warn "using Termux d8 - it crashes on anonymous classes; set R8_JAR"
else
  die "no dexer: $R8_JAR missing and d8 not installed"
fi
"${DEXER[@]}" --release --lib "$ANDROID_JAR" --min-api "$MIN_API" --output "$OUT/dex" \
  $(find "$OUT/classes" -name '*.class')

echo "==> package"
cp "$OUT/apk/base.apk" "$OUT/apk/unaligned.apk"
(cd "$OUT/dex" && zip -q -X -j "$OLDPWD/$OUT/apk/unaligned.apk" classes.dex)
if [ -d assets ] && [ -n "$(ls -A assets 2>/dev/null)" ]; then
  (cd assets && zip -q -X -r "$OLDPWD/$OUT/apk/unaligned.apk" .)
fi

echo "==> sign (v1+v2+v3)"
if [ ! -f "$ANDROID_KEYSTORE" ]; then
  mkdir -p "$(dirname "$ANDROID_KEYSTORE")"
  need keytool openjdk-21
  keytool -genkeypair -keystore "$ANDROID_KEYSTORE" -alias "$ANDROID_KS_ALIAS" \
    -storepass "$ANDROID_KS_PASS" -keypass "$ANDROID_KS_PASS" -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
apksigner sign --ks "$ANDROID_KEYSTORE" --ks-pass "pass:$ANDROID_KS_PASS" \
  --key-pass "pass:$ANDROID_KS_PASS" --out "$APK_NAME" "$OUT/apk/unaligned.apk"

echo "==> ok: $PWD/$APK_NAME ($(stat -c%s "$APK_NAME") bytes)"
aapt dump badging "$APK_NAME" 2>/dev/null \
  | grep -E "^package|application-label:|launchable-activity" | sed 's/^/    /' || true
