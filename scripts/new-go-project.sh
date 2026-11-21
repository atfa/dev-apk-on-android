#!/usr/bin/env sh
# Scaffold an on-device Android project whose business logic is Go (cgo + JNI, no Gradle,
# no NDK, no gomobile). Everything is built on the phone by the copied build.sh.
#
#   usage: new-go-project.sh <dir> <package> [label] [tag]
#   e.g.   sh scripts/new-go-project.sh $HOME/apps/goapp com.example.goapp "Go App" goapp
#
# Adds to what new-project.sh makes: a go/ module (JNI bridge + pure-Go tests + optional
# net/http server for a WebView UI), a thin Java shell, and the app.env/manifest switches.
# See references/go-native.md for the rules this scaffold encodes.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SKILL="$HERE"
[ -f "$SKILL/templates/AndroidManifest.xml" ] || SKILL=$(cd "$HERE/.." && pwd)
LIB="$SKILL/lib"; [ -f "$LIB/common.sh" ] || LIB="$HERE/lib"
. "$LIB/common.sh"

DIR="${1:?usage: new-go-project.sh <dir> <package> [label] [tag]}"
PKG="${2:?usage: new-go-project.sh <dir> <package> [label] [tag]}"
LABEL="${3:-${PKG##*.}}"
TAG="${4:-${PKG##*.}}"
[ -d "$SKILL/templates/go" ] || die "templates/go not found next to $0"

# JNI symbol names are the package with '.' -> '_'; a '_' inside the package name would need
# the _1 mangling, so refuse it instead of producing symbols the runtime cannot resolve.
case "$PKG" in
  *_*) die "package name must not contain '_' (JNI name mangling): $PKG" ;;
esac
PKG_UNDER=$(echo "$PKG" | tr '.' '_')
PKGPATH=$(echo "$PKG" | tr '.' '/')
GO_LIB=${GO_LIB:-$(echo "$TAG" | tr -c 'a-z0-9' ' ' | tr -d ' ')}
GO_BIN=${GO_BIN:-${GO_LIB}bin}
[ -n "$GO_LIB" ] || die "GO_LIB is empty: pass a lowercase alphanumeric tag, or set GO_LIB=..."

sh "$HERE/new-project.sh" "$DIR" "$PKG" "$LABEL" "$TAG"
cd "$DIR"

gosub() {   # gosub <template> <dest>
  sed -e "s|__PKG_UNDERSCORE__|$PKG_UNDER|g" -e "s|__PACKAGE__|$PKG|g" \
      -e "s|__PKGPATH__|$PKGPATH|g" -e "s|__GO_LIB__|$GO_LIB|g" \
      -e "s|__GO_BIN__|$GO_BIN|g" -e "s|__TAG__|$TAG|g" "$1" > "$2"
}

# --- go/ module ---------------------------------------------------------------------
mkdir -p go/bin
gosub "$SKILL/templates/go/main.go" go/main.go
gosub "$SKILL/templates/go/web.go" go/web.go
cp "$SKILL/templates/go/main_test.go" go/main_test.go
cp "$SKILL/templates/go/bin/main.go" go/bin/main.go
if command -v go >/dev/null 2>&1; then
  ( cd go && go mod init "$PKG" >/dev/null 2>&1 ) || warn "go mod init failed"
else
  warn "no go in PATH: run 'pkg install golang', then 'cd go && go mod init $PKG'"
  printf 'module %s\n\ngo 1.24\n' "$PKG" > go/go.mod
fi

# --- Java shell: replaces the pure-Java template ------------------------------------
gosub "$SKILL/templates/go/src/__PKGPATH__/MainActivity.java" "src/$PKGPATH/MainActivity.java"
gosub "$SKILL/templates/go/src/__PKGPATH__/GoWebViewActivity.java" "src/$PKGPATH/GoWebViewActivity.java"

# --- manifest: native libs, localhost http, the WebView activity --------------------
if [ -n "${PY:-}" ]; then
  MANIFEST=AndroidManifest.xml GO_LIB=$GO_LIB "$PY" - <<'PYEOF'
import os
p = os.environ["MANIFEST"]
s = open(p).read()
s = s.replace('android:debuggable="true">',
              'android:debuggable="true"\n        android:extractNativeLibs="true"\n'
              '        android:usesCleartextTraffic="true">')
s = s.replace('    <application',
              '    <uses-permission android:name="android.permission.INTERNET" />\n\n    <application', 1)
s = s.replace('    </application>',
              '        <activity\n            android:name=".GoWebViewActivity"\n'
              '            android:exported="false"\n'
              '            android:theme="@android:style/Theme.Material.NoActionBar.Fullscreen" />\n'
              '    </application>')
open(p, "w").write(s)
PYEOF
else
  warn "no python3: patching the manifest with sed (check extractNativeLibs by hand)"
  sed -i 's|android:debuggable="true">|android:debuggable="true" android:extractNativeLibs="true" android:usesCleartextTraffic="true">|' AndroidManifest.xml
fi

# --- app.env: the knobs build.sh reads ----------------------------------------------
cat >> app.env <<EOF
# --- Go native layer (see references/go-native.md) -----------------------------------
GO_DIR=go                    # go module with the business logic
GO_LIB=$GO_LIB               # -> lib/<abi>/lib$GO_LIB.so  (System.loadLibrary("$GO_LIB"))
GO_BIN=$GO_BIN               # -> lib/<abi>/lib$GO_BIN.so  (exec'd by Java; pure Go, no cgo)
GO_LDFLAGS=\${GO_LDFLAGS:--s -w}
GO_FLAGS=\${GO_FLAGS:-}
EOF

cat >> README.md <<EOF

## Go business logic

    ./build.sh && ./install.sh && ./test.sh        # GO_TEST=1 ./build.sh also runs go test

* \`go/main.go\`  business logic + JNI exports (\`Java_${PKG_UNDER}_MainActivity_*\`)
* \`go/web.go\`   net/http server + HTML page: the WebView UI variant
* \`go/bin/\`     pure-Go binary, exec'd by Java (no JNI)
* \`src/$PKGPATH/MainActivity.java\` thin shell: View, lifecycle, \`System.loadLibrary("$GO_LIB")\`
* hooks: \`am start -n $PKG/.MainActivity --es hook async|threads|webtest|web|exec\`
* the Go side writes \`files/from-go.txt\`; read logs with \`su --mount-master -c "cat ..."\`

Rules worth knowing before you edit go/main.go: cgo cannot call JNIEnv's function-pointer
table (use the C helpers in the preamble), a Go panic that reaches the JVM kills the app
(every export recovers), a goroutine that outlives the call needs a global ref and must
attach its thread to the JVM, and JNI calls cost ~0.3 us each so batch them.
EOF

say "created $DIR (Go business logic, lib$GO_LIB.so)"
say "next: cd $DIR && ./build.sh && ./install.sh && ./test.sh"
