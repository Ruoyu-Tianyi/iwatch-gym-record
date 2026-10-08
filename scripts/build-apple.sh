#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
rm -rf artifacts/iOS.xcresult artifacts/watchOS.xcresult
xcodebuild -project RepFlow.xcodeproj -scheme RepFlow \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData/iOS -resultBundlePath artifacts/iOS.xcresult \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee artifacts/iOS-build.log
xcodebuild -project RepFlow.xcodeproj -scheme RepFlowWatch \
  -configuration Debug -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath DerivedData/watchOS -resultBundlePath artifacts/watchOS.xcresult \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee artifacts/watchOS-build.log
