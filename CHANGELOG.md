# 0.2.0

## Background virtual display: debug without stealing the phone

`am start` used to take over the panel, so a long test made the phone unusable. With root the app
can now run on a virtual display that nothing mirrors: it renders, takes injected touches, can be
screenshotted, and keeps running with the screen off, while display 0 keeps showing whatever you
had open.

* `vendor/vd/Vd.java` - a ~300-line daemon run through `app_process` that owns the
  `VirtualDisplay`, captures it through an `ImageReader` and answers commands from a file
  (`shot`, `size`, `rotate`, `power`, `ping`, `quit`). Prebuilt to `vendor/vd/vd.jar` (7 KB),
  rebuildable with `scripts/vd-build.sh`.
* `scripts/vd.sh` - the driver: `create [WxH@dpi]`, `destroy`, `status`, `id`, `size`, `shot`,
  `tap`, `swipe`, `key`, `text`, `launch`, `rotate`, `log`. Tap coordinates are screenshot
  pixels; the driver inverts the shot rotation.
* Display flag values move between Android versions (`TRUSTED` is `0x40` on 10-13, `0x400` on
  16), so they are read from the framework by name at runtime instead of being hard-coded.
* A display in its own display group starts OFF and renders nothing; the daemon sets a power
  override (`setOverrideDisplayState`, with fallbacks, since `setVirtualDisplayState` is gone on
  Android 16), which is also what keeps the app rendering with the panel off.
* Landscape apps are drawn rotated inside the display's base buffer and `Display.getRotation()`
  reports 0 for them, so the rotation is read from the app window transform in `dumpsys input`
  and undone: shots come out upright and taps line up.
* Wired into the normal flow: `install.sh --bg`, `screen.sh --vd`, `test.sh --vd`, and
  `probe.sh` now reports focus per display (the app on 131, Termux on 0).
* `settings put global overlay_display_devices` documented as the no-daemon fallback (leaves a
  thumbnail on the panel); without root `vd.sh` exits 3 with a message.
* Verified on Android 16 (vivo V2366HA, KernelSU): create -> launch -> shot -> tap -> screen-off
  rendering -> destroy, with the plant game and a scaffolded test app.

## Fixed

* `vd.sh status` printed nothing under "your screen is showing": the awk pattern required a
  trailing space after `mDisplayId=0`, and that line usually ends right there. Selfcheck now
  asserts that line is non-empty, so the regression cannot come back.

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
