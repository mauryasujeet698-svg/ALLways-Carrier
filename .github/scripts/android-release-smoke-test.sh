#!/usr/bin/env bash
set -euo pipefail

PACKAGE_NAME="${1:?Package name is required}"
APK="build/app/outputs/flutter-apk/app-release.apk"
test -s "$APK"

adb wait-for-device
ready=0
for attempt in $(seq 1 90); do
  boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [ "$boot" = "1" ]; then
    ready=1
    break
  fi
  sleep 2
done
if [ "$ready" != "1" ]; then
  echo "::error::Android emulator did not finish booting."
  adb logcat -d -t 1500 | tail -n 300 || true
  exit 1
fi

adb logcat -c || true
installed=0
for attempt in $(seq 1 8); do
  echo "Release APK install attempt $attempt/8"
  if adb install -r "$APK"; then
    installed=1
    break
  fi
  sleep 5
done
if [ "$installed" != "1" ]; then
  echo "::error::Release APK could not be installed on the emulator."
  adb devices -l || true
  adb logcat -d -t 1800 | tail -n 350 || true
  exit 1
fi

echo "Starting $PACKAGE_NAME release-mode build."
if ! timeout 90s adb shell am start -W -n "$PACKAGE_NAME/.MainActivity"; then
  echo "::error::Android failed to start $PACKAGE_NAME/.MainActivity."
  adb logcat -d -t 2500 | grep -E "FATAL EXCEPTION|AndroidRuntime|Process: $PACKAGE_NAME|Unable to start activity|ActivityTaskManager" | tail -n 150 || true
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' || true
  exit 1
fi

sleep 15
if ! adb shell pidof "$PACKAGE_NAME" >/dev/null; then
  echo "::error::$PACKAGE_NAME process exited after launch."
  adb logcat -d -t 2500 | grep -E "FATAL EXCEPTION|AndroidRuntime|Process: $PACKAGE_NAME|Unable to start activity" | tail -n 150 || true
  exit 1
fi
if adb logcat -d -t 2500 | grep -E "FATAL EXCEPTION.*$PACKAGE_NAME|Process: $PACKAGE_NAME.*died"; then
  echo "::error::$PACKAGE_NAME startup logs contain a fatal crash."
  exit 1
fi

echo "$PACKAGE_NAME release-mode launch check passed."
