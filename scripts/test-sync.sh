#!/usr/bin/env bash
# Exercises the actual AppStore with a tiny test-only transport/Combine surface.
# Apple framework type checking and device delivery remain separate checks.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swiftc >/dev/null 2>&1; then
  echo '需要 Swift 5.9+ 工具链并将 swiftc 加入 PATH。' >&2
  exit 1
fi
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
case "$(uname -s)" in
  Darwin) library_ext=dylib ;;
  *) library_ext=so ;;
esac
swiftc -swift-version 5 -emit-library -emit-module -module-name Combine \
  Tests/SyncHarness/CombineStub.swift -emit-module-path "$check_dir/Combine.swiftmodule" \
  -o "$check_dir/libCombine.$library_ext"
swiftc -swift-version 5 -emit-library -emit-module -module-name RepFlowCore \
  Sources/RepFlowCore/*.swift -emit-module-path "$check_dir/RepFlowCore.swiftmodule" \
  -o "$check_dir/libRepFlowCore.$library_ext"
swiftc -swift-version 5 -I "$check_dir" -L "$check_dir" -lCombine -lRepFlowCore \
  -Xlinker -rpath -Xlinker "$check_dir" \
  Shared/AppStore.swift Tests/SyncHarness/ConnectivityStub.swift Tests/SyncHarness/StoreHarness.swift \
  -o "$check_dir/store-tests"
"$check_dir/store-tests"
