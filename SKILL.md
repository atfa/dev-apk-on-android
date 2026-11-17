---
name: dev-apk-on-android
description: Build, sign, install and drive Android APKs entirely on the Android phone from Termux - no PC, no Android Studio, no Gradle. Use when asked to write an Android app, compile Java/Kotlin into an .apk, sign it, install or launch it on this device, drive it from a shell script, or when an on-device build fails (aapt2, d8/R8, javac aborting, pm install hanging, zipalign).
license: MIT
compatibility: Android 7+ (minSdk 24), Termux arm64/armv7 with aapt2 + apksigner + openjdk-21; root (Magisk/KernelSU/sudo) optional - it upgrades install/verify from manual to automatic
metadata:
  offline: "yes - the 38 MB toolchain ships in vendor/, no download after the first pkg install"
  platforms: android
---

# Build an Android APK on the phone

Everything - edit, compile, dex, package, sign, install, launch, verify - happens on the
device. The on-device toolchain is `aapt2`/`apksigner` from Termux plus one Java jar.

```
resources  aapt2 compile / aapt2 link        Termux package, native aarch64
sources    javac -source 8 -target 8         openjdk-21 + -bootclasspath android.jar
classes    d8                                vendor/r8-*.jar (NOT Termux `d8`)
package    zip classes.dex into the linked apk
sign       apksigner v1+v2+v3                ~/.android/debug.keystore
install    pm install -r -g (root)  |  termux-open (one tap, no root)
verify     dumpsys / logcat / the app's own files/testlog.txt
```

## Quick start

```sh
S=<this skill>/scripts
sh $S/setup-toolchain.sh                                   # offline: verifies + installs vendor/
sh $S/new-project.sh $HOME/apps/myapp com.example.myapp "My App"
cd $HOME/apps/myapp && ./build.sh && ./install.sh && ./test.sh
```

`new-project.sh` copies everything a project needs (scripts + lib/ + templates), so the
project keeps working even if this skill is moved or deleted. Its `README.md` lists the
files. `./build.sh` is bash - never call it as `sh build.sh`.

## Verify what you built, not what you assume

A model cannot look at a screenshot, and logcat is unreliable on a busy phone. Make the app
write its state to `files/testlog.txt` (the template Activity does) and read that file back:

```sh
./probe.sh com.example.myapp        # foreground? crashed? (root)
./screen.sh 60                      # screenshot -> ASCII art (root)
./log.sh mytag                      # logcat lines, when logcat is readable
su --mount-master -c "cat /data/data/com.example.myapp/files/testlog.txt"
```

Drive the app through hooks instead of taps: `am start ... --es hook ping` for cold starts and
a `files/testhook` file for a warm app (Android 14+ drops the extras when the activity is
already on top). Details and the fail-modes of this harness: `references/testing.md`.

## Rules that break on-device builds

1. **Never use Termux's `d8`** for JDK-compiled classes: it is R8 3.3 and dies with
   `NullPointerException: Cannot invoke "String.length()"` on anonymous classes (JDK 11+
   `NestMembers`). Always `java -cp <r8.jar> com.android.tools.r8.D8`.
2. **javac flags**: JDK 21 rejects `--release`/`-target 11` together with `-bootclasspath`.
   Use `-source 8 -target 8 -bootclasspath android.jar`.
3. **`aapt2 link` needs the full `android.jar`** because it resolves `@android:` resources from
   the framework resource table. A "classes only" jar links nothing (measured: silently fails
   with `attribute android:versionCode not found`).
4. **`aapt2 link` takes compiled resources as positional args**, not `-R`:
   `aapt2 link -o base.apk -I android.jar --manifest AndroidManifest.xml res.zip --java gen/`.
5. **javac dies with exit 134** and `Native registration unable to find class ...
   PerfettoTrace` until the Perfetto stub is in place - that is the broken Termux JDK, not your
   code. `setup-toolchain.sh` fixes it; `java -version` working proves nothing.
6. **No `zipalign` on device.** A pure Java/Kotlin APK installs fine unaligned. With native
   libs set `android:extractNativeLibs="true"`.
7. **Non-root `pm install` is dead on Android 11+** (`SecurityException: user -1`). Use root,
   or `termux-open app.apk` and tap Install once.
8. **Stage the apk in `/data/local/tmp`** before `pm install`: `system_server` opens the file
   and cannot read `/data/data/com.termux/...`.

`references/pitfalls.md` has the full list with the exact error text; read it when a step
fails. `references/build.md` explains the toolchain, `references/install.md` the install and
launch traps, `references/vendor.md` the bundled binaries.

## Root is optional

| step | with root | without root |
|---|---|---|
| build, sign | yes | yes |
| install | `pm install -r -g` + `am start`, unattended | `termux-open`, one tap |
| probe / logcat / screencap | yes | not available |
| automated acceptance test | yes | builds, installs, then stops |

Every script degrades with a message instead of failing: `test.sh` exits 3 ("skipped") when
there is no root, so a CI-ish loop can tell "not verified" from "failed". `APK_NO_ROOT=1`
forces the fallback path for testing.

## A scaffolded project

```
AndroidManifest.xml   no <uses-sdk>: minSdk/targetSdk are passed by build.sh
app.env               APP_PACKAGE / ACTIVITY / APK_NAME / TAG / PLATFORM_API / MIN_API
src/<pkg path>/       Java sources
res/                  resources (launcher icons: $PY gen_icon.py A)
assets/               packaged as-is
lib/                  config.sh + root.sh shared by the copied scripts
build.sh install.sh test.sh probe.sh log.sh screen.sh
```

`app.env` is the single source of truth for api levels; an environment variable wins over it,
e.g. `PLATFORM_API=34 ./build.sh` as soon as `vendor/android-34-android.jar` exists.

## Offline, and changing versions

`vendor/` ships the two jars (38 MB) with `SHA256SUMS`; `setup-toolchain.sh` verifies and
copies them into `$ANDROID_HOME` / `$ANDROID_TOOLS` and never downloads when they are there.
Only `pkg install` needs the network, and only on a fresh Termux. Only API 33 is bundled -
`vendor/MANIFEST.md` shows how to add another API level or a newer R8 in two commands.

## Not covered here

Kotlin (`kotlinc` in the Termux repo, then feed `.class` to d8), native code (Rust/NDK, ship a
`.so` and set `extractNativeLibs`), and Gradle/AGP on device (works, but needs
`android.aapt2FromMavenOverride=$PREFIX/bin/aapt2` and `zipAlignEnabled = false`). For large
multi-module projects, build in CI and `termux-open` the artifact.
