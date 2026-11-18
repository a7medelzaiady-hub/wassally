#!/usr/bin/env bash
# Runs inside reactivecircus/android-emulator-runner, after the emulator has started.
# Installs the debug APK with explicit readiness checks and timeouts, then runs Maestro.
# Diagnostics are always collected (also on failure) into ./diagnostics.
set -euo pipefail

APK="build/app/outputs/flutter-apk/app-debug.apk"
APP_ID="com.wassally.app"
OUT="diagnostics"
mkdir -p "$OUT"

collect_diagnostics() {
  echo "::group::Collecting diagnostics"
  adb devices -l > "$OUT/adb-devices.txt" 2>&1 || true
  adb logcat -d -v threadtime > "$OUT/logcat.txt" 2>&1 || true
  adb shell getprop > "$OUT/getprop.txt" 2>&1 || true
  adb shell dumpsys package "$APP_ID" > "$OUT/dumpsys-package.txt" 2>&1 || true
  adb shell screencap -p /sdcard/final.png 2>/dev/null && adb pull /sdcard/final.png "$OUT/final-screen.png" >/dev/null 2>&1 || true
  df -h > "$OUT/df.txt" 2>&1 || true
  free -m > "$OUT/free.txt" 2>&1 || true
  ls -l /dev/kvm > "$OUT/kvm.txt" 2>&1 || true
  echo "::endgroup::"
}
trap collect_diagnostics EXIT

# Prints ADB state with a hard timeout per command, so a hung adb shows up as a
# clear failure line instead of silently stalling the job.
adb_snapshot() {
  local label="$1"
  echo "::group::ADB diagnostics ($label)"
  timeout 30 adb devices -l || echo "WARN: 'adb devices' failed or timed out"
  timeout 30 adb get-state || echo "WARN: 'adb get-state' failed or timed out"
  timeout 30 adb shell getprop ro.build.fingerprint || echo "WARN: getprop failed or timed out"
  timeout 30 adb shell getprop sys.boot_completed || echo "WARN: boot_completed check failed"
  timeout 30 adb shell df /data || echo "WARN: 'df /data' failed or timed out"
  timeout 30 adb shell pm list packages -3 || echo "WARN: 'pm list packages' failed or timed out"
  echo "::endgroup::"
}

echo "::group::Wait for device and package manager"
timeout 120 adb wait-for-device
timeout 300 bash -c 'until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d "\r")" = "1" ]; do sleep 2; done'
timeout 180 bash -c 'until adb shell pm path android 2>/dev/null | grep -q "^package:"; do sleep 2; done'
adb shell getprop ro.build.version.sdk
echo "::endgroup::"

adb_snapshot "before install"

echo "::group::Install APK"
ls -lh "$APK"
timeout 300 adb install -r -t "$APK"
timeout 30 adb shell pm path "$APP_ID" | grep -q "^package:"
echo "App package is installed: $APP_ID"
echo "::endgroup::"

adb_snapshot "after install"

echo "::group::Maestro login smoke flow"
maestro test \
  --format junit \
  --output "$OUT/maestro-report.xml" \
  --debug-output "$OUT/maestro-debug" \
  .maestro/flows/login-smoke.yaml
echo "::endgroup::"
