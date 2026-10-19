#!/bin/sh
# Runs the integration tests in Chrome (headless, with a fake microphone).
#   tool/integration_web.sh [--no-headless]
# Downloads a chromedriver matching the installed Chrome into .chromedriver/.
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
VERSION=$("$CHROME" --version | awk '{print $3}')
DRIVER=$(ls -d .chromedriver/chromedriver/*-"$VERSION"/*/chromedriver 2>/dev/null | head -1)
if [ -z "$DRIVER" ]; then
  npx --yes @puppeteer/browsers@2.10.5 install "chromedriver@$VERSION" --path "$PWD/.chromedriver" >/dev/null || true
  DRIVER=$(ls -d .chromedriver/chromedriver/*-"$VERSION"/*/chromedriver 2>/dev/null | head -1)
  if [ -z "$DRIVER" ]; then
    # The download can leave only the zip behind: extract it.
    ZIP=$(ls .chromedriver/chromedriver/"$VERSION"-*.zip | head -1)
    unzip -o -q "$ZIP" -d ".chromedriver/chromedriver/mac-$VERSION"
    DRIVER=$(ls -d .chromedriver/chromedriver/*-"$VERSION"/*/chromedriver | head -1)
  fi
fi

"$DRIVER" --port=4444 >/dev/null 2>&1 &
DRIVER_PID=$!
trap 'kill $DRIVER_PID 2>/dev/null || true' EXIT
sleep 1

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/editor_test.dart \
  -d web-server --browser-name=chrome --driver-port=4444 \
  --web-browser-flag=--use-fake-ui-for-media-stream \
  --web-browser-flag=--use-fake-device-for-media-stream \
  --web-browser-flag=--autoplay-policy=no-user-gesture-required \
  "$@"
