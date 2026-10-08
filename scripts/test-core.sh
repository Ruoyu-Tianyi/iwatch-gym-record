#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swift >/dev/null 2>&1; then
  echo '需要 Swift 5.9+。macOS 可使用 Xcode 工具链，Linux 可从 swift.org 安装。' >&2
  exit 1
fi
swift test
