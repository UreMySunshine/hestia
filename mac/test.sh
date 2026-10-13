#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC="$ROOT/mac"
export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
TEST_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/hestia-swift-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

cargo build --manifest-path "$ROOT/core/Cargo.toml"
swiftc -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
  -sdk "$SDKROOT" -module-cache-path "$TEST_DIR/cache" \
  -I "$MAC/Bridge" -L "$ROOT/core/target/debug" -lhestia_core \
  -Xlinker -rpath -Xlinker "$ROOT/core/target/debug" \
  "$MAC/Sources/Core/Models.swift" "$MAC/Sources/Core/Store.swift" \
  "$MAC/Sources/Core/Bridge.swift" "$MAC/Sources/Core/LoginItem.swift" \
  "$MAC/Sources/Design/Theme.swift" "$MAC/Sources/Design/Icons.swift" \
  "$MAC/Sources/Design/Components.swift" "$MAC/Sources/Design/SVGPath.swift" \
  "$MAC/Sources/Design/PopUpMenu.swift" "$MAC/Sources/Design/Format.swift" \
  "$MAC/Tests/BehaviorTests.swift" -o "$TEST_DIR/behavior-tests"
"$TEST_DIR/behavior-tests"
