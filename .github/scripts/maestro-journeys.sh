#!/usr/bin/env bash
# يشتغل داخل android-emulator-runner: يشغّل Firebase Emulators (Auth + Firestore) على الـ runner،
# يزرع بيانات تجريبية، يثبّت نسخة debug (WASALLY_E2E=true) ويشغّل رحلات Maestro بالترتيب.
set -uo pipefail

APK="build/app/outputs/flutter-apk/app-debug.apk"
OUT="diagnostics-journeys"
mkdir -p "$OUT"

cleanup() {
  adb logcat -d -v threadtime > "$OUT/logcat.txt" 2>&1 || true
  adb shell screencap -p /sdcard/final.png 2>/dev/null && adb pull /sdcard/final.png "$OUT/final-screen.png" >/dev/null 2>&1 || true
  [ -n "${EMU_PID:-}" ] && kill "$EMU_PID" 2>/dev/null || true
}
trap cleanup EXIT

timeout 300 adb wait-for-device
timeout 300 bash -c 'until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d "\r")" = "1" ]; do sleep 2; done'
timeout 300 adb install -r -t "$APK" || exit 1

echo "::group::Start Firebase Emulators"
(
  export JAVA_HOME="$JAVA21_HOME"
  export PATH="$JAVA_HOME/bin:$PATH"
  cd rules-tests
  exec npx firebase emulators:start --config ../firebase.e2e.json --only auth,firestore --project demo-wasally
) > "$OUT/emulators.log" 2>&1 &
EMU_PID=$!
for i in $(seq 1 90); do
  if curl -s -o /dev/null http://127.0.0.1:8080 && curl -s -o /dev/null http://127.0.0.1:9099; then break; fi
  sleep 2
done
curl -s -o /dev/null http://127.0.0.1:8080 || { echo "Firestore emulator did not start"; tail -50 "$OUT/emulators.log"; exit 1; }
curl -s -o /dev/null http://127.0.0.1:9099 || { echo "Auth emulator did not start"; tail -50 "$OUT/emulators.log"; exit 1; }
echo "::endgroup::"

node e2e/seed.mjs || exit 1

status=0
for flow in .maestro/journeys/0*.yaml; do
  name=$(basename "$flow" .yaml)
  echo "::group::Maestro $name"
  if ! maestro test --format junit --output "$OUT/$name.xml" --debug-output "$OUT/debug-$name" "$flow"; then
    status=1
    echo "::error::Journey failed: $name"
    echo "--- visible texts on screen at failure (uiautomator):"
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb pull /sdcard/ui.xml "$OUT/ui.xml" >/dev/null 2>&1 || true
    grep -oE '(text|content-desc)="[^"]+"' "$OUT/ui.xml" 2>/dev/null | sort -u | head -80 || true
    adb logcat -d -v threadtime -s flutter:V 2>/dev/null | grep -vE "ListTile|DecoratedBox|CRASHLYTICS|-----|Another exception|To fix this" | tail -60 || true
    echo "::endgroup::"
    break
  fi
  echo "::endgroup::"
done
echo "--- emulator log tail:"; tail -20 "$OUT/emulators.log" || true
exit $status
