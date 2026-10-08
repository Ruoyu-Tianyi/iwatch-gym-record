#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo '此脚本需要安装完整 Xcode 的 Mac。Linux 只支持 scripts/test-core.sh。' >&2
  exit 1
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo '请安装完整 Xcode，在 Xcode > Settings > Locations 选择 Command Line Tools。' >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo '请先安装 XcodeGen 2.44.1 或更新版本：brew install xcodegen' >&2
  exit 1
fi
xcodegen generate --spec project.yml
xcodebuild -list -project RepFlow.xcodeproj
echo '工程已生成。打开 RepFlow.xcodeproj，为两个 target 设置你的 Team 和唯一 Bundle ID。'
