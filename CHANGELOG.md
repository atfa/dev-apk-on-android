# 0.1.0

First public version, extracted from private experiments building games and utilities on a
phone with Termux. Everything below was verified on-device with `scripts/selfcheck.sh`.

## Build

* One pipeline for all five steps: aapt2 compile/link, javac (JDK 21, `-source/-target 8` with
  a `android.jar` bootclasspath), d8 from a vendored R8, zip, apksigner v1+v2+v3.
* API levels live in `app.env` and are passed to `aapt2 link`; the template manifest carries no
  `<uses-sdk>`, so the two cannot drift.
* Termux `d8` is never used: it is R8 3.3 and dies on `NestMembers` from anonymous classes.
* The Termux JDK startup abort (`PerfettoTrace`) is repaired by generating a stub jar from the
  device's own `libperfetto_framework_jni.so`, then wrapping every JDK tool's bootclasspath.
  Both 64- and 32-bit library paths are probed.

## Toolchain

* Fully offline: `vendor/` ships `android-33-android.jar` (27 MB) and a repacked R8 (11 MB,
  `resources/` stripped - verified to dex) with `SHA256SUMS` and `MANIFEST.md`. Only
  `pkg install` needs the network.
* `verify-vendor.sh` checks size, checksum, that `D8.class` and the framework resources are
  present, and dexes a real class. `selfcheck.sh` runs scaffold -> build -> install -> test.
* Applying a different api level, R8 version or key is done with environment variables; no
  script edits.

## Install / launch

* Root: stage the apk in `/data/local/tmp`, `pm install -r -g`, HOME-then-start for Android 14+,
  and a retry that disables OEM package verifiers when the install hangs on a dialog.
* No root: `termux-open` with one tap, and a clear statement of what cannot be verified.
* One root abstraction (`lib/root.sh`) for `su` / `sudo` / already-root / none, including the
  global mount namespace where app data is only visible - for reads *and* writes.

## Testing

* Test hooks: intent extras for cold starts, a polled `files/testhook` file for a warm app.
* The app writes its own `files/testlog.txt`; assertions poll that file instead of logcat,
  which is evicted by system noise on busy phones.
* `probe.sh` reports foreground state from two sources (`dumpsys window`, then
  `dumpsys activity activities`) and prints the crash buffer.
* `screen.sh` turns a screenshot into ASCII art for models that cannot see images.
* `test.sh` exits 3 ("skipped") instead of failing when there is no root.

## Compared to the private version

* Every hard-coded path, package name, device name and download url is gone; all tunables are
  in `lib/config.sh` and documented in the reference files.
* Duplicated documentation was merged; `vendor/MANIFEST.md` exists now; the scaffold copies
  exactly the scripts the docs promise.
* The 67 MB platform zip is no longer shipped (the extracted jar is).
* Added `selfcheck.sh`, `verify-vendor.sh`, `APK_NO_ROOT` and the no-root code paths.
