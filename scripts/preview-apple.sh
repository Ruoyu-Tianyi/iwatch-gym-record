#!/usr/bin/env bash
# Run only on a Mac with iOS/watchOS simulator runtimes installed.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts/screenshots
xcrun simctl list devices available --json > artifacts/simulator-devices.json
for platform in iOS watchOS; do
  device_id=$(python3 - "$platform" <<'PY'
import json, re, sys
platform = sys.argv[1]
with open('artifacts/simulator-devices.json') as stream:
    devices = json.load(stream)['devices']
choices = []
for runtime, rows in devices.items():
    if f'.{platform}-' not in runtime:
        continue
    version = tuple(map(int, re.findall(r'\d+', runtime)))
    for row in rows:
        if row.get('isAvailable') and (platform != 'iOS' or row['name'].startswith('iPhone')):
            choices.append((version, row['name'], row['udid']))
print(max(choices)[2] if choices else '')
PY
  )
  if [[ -z "$device_id" ]]; then
    echo "$platform simulator runtime unavailable; preview skipped." >> artifacts/screenshots/status.txt
    continue
  fi
  xcrun simctl boot "$device_id" 2>/dev/null || true
  xcrun simctl bootstatus "$device_id" -b
  if [[ "$platform" == 'iOS' ]]; then
    app_path='DerivedData/iOS/Build/Products/Debug-iphonesimulator/RepFlow.app'
    bundle_id='com.example.RepFlow'
  else
    app_path='DerivedData/watchOS/Build/Products/Debug-watchsimulator/RepFlowWatch.app'
    bundle_id='com.example.RepFlow.watchkitapp'
  fi
  if xcrun simctl install "$device_id" "$app_path" && xcrun simctl launch "$device_id" "$bundle_id"; then
    sleep 5
    xcrun simctl io "$device_id" screenshot "artifacts/screenshots/$platform.png"
    echo "$platform app launched successfully." >> artifacts/screenshots/status.txt
  else
    echo "$platform app failed to launch; inspect the build and simulator logs." >> artifacts/screenshots/status.txt
    exit 1
  fi
  xcrun simctl shutdown "$device_id"
done
