#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ID="${1:?Usage: android-release-smoke.sh <applicationId> <label> [apk-path]}"
APP_LABEL="${2:?Usage: android-release-smoke.sh <applicationId> <label> [apk-path]}"
APK="${3:-build/app/outputs/flutter-apk/app-release.apk}"

echo "Smoke-testing ${APP_LABEL} (${PACKAGE_ID})"
test -s "${APK}" || { echo "::error::Release APK missing or empty: ${APK}"; exit 1; }

adb wait-for-device
ready=0
for attempt in $(seq 1 90); do
  boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [[ "${boot}" == "1" ]] && adb shell cmd package list packages >/dev/null 2>&1 && adb shell dumpsys activity activities >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done

if [[ "${ready}" != "1" ]]; then
  echo "::error::Android emulator services did not become ready."
  adb devices -l || true
  adb logcat -d -t 2000 | tail -n 300 || true
  exit 1
fi

adb logcat -c
installed=0
for attempt in $(seq 1 6); do
  echo "APK install attempt ${attempt}/6"
  if adb install -r "${APK}"; then
    installed=1
    break
  fi
  sleep 5
done

if [[ "${installed}" != "1" ]]; then
  echo "::error::Release APK could not be installed after retries."
  adb devices -l || true
  adb shell getprop sys.boot_completed || true
  adb logcat -d -t 2500 | tail -n 350 || true
  exit 1
fi

if ! timeout 90s adb shell am start -W -n "${PACKAGE_ID}/.MainActivity"; then
  echo "::error::Android failed to start ${PACKAGE_ID}/.MainActivity."
  adb logcat -d -t 2500 | grep -E 'FATAL EXCEPTION|AndroidRuntime|Unable to start activity|ActivityTaskManager' | tail -n 180 || true
  adb shell dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' || true
  exit 1
fi

sleep 15
if ! adb shell pidof "${PACKAGE_ID}" >/dev/null; then
  echo "::error::${APP_LABEL} process exited after launch."
  adb logcat -d -t 2500 | grep -E 'FATAL EXCEPTION|AndroidRuntime|Unable to start activity|Process:' | tail -n 180 || true
  exit 1
fi

if adb logcat -d -t 2500 | grep -E "FATAL EXCEPTION.*${PACKAGE_ID}|Process: ${PACKAGE_ID}.*died"; then
  echo "::error::${APP_LABEL} startup logs contain a fatal crash."
  exit 1
fi

echo "${APP_LABEL} release-mode launch check passed."
