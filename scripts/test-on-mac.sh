#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo "Install Xcode on macOS and select it with xcode-select first." >&2
  exit 1
fi
xcodebuild -version
if [ -z "${DAYMARK_DESTINATION:-}" ]; then
  device_id=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; data=json.load(sys.stdin); print(next(d["udid"] for k,ds in data["devices"].items() if "iOS" in k for d in ds if d["name"].startswith("iPhone")))')
  DAYMARK_DESTINATION="platform=iOS Simulator,id=$device_id"
fi
xcodebuild test -project Daymark.xcodeproj -scheme Daymark \
  -destination "$DAYMARK_DESTINATION" \
  -derivedDataPath build/DerivedData -resultBundlePath build/DaymarkTests.xcresult \
  CODE_SIGNING_ALLOWED=NO
