#!/bin/sh
# Runs the integration tests on an Android device or emulator.
#   tool/integration_android.sh [device-id]     (default: the only device)
# `flutter test` reinstalls the app, which resets the microphone permission,
# and a test can't tap the system dialog: grant it as soon as the app is in.
set -e
cd "$(dirname "$0")/.."
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
DEVICE="${1:-$("$ADB" devices | awk 'NR==2 {print $1}')}"
APP=com.amedaz.aminotes_example

(for _ in $(seq 1 600); do
  "$ADB" -s "$DEVICE" shell pm grant "$APP" android.permission.RECORD_AUDIO 2>/dev/null && exit 0
  sleep 0.5
done) &
GRANT=$!
trap 'kill $GRANT 2>/dev/null || true' EXIT

flutter test integration_test -d "$DEVICE"
