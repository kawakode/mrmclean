#!/bin/bash
# Opens real app views with in-memory fixtures. Close with Ctrl-C in this terminal.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN_DIR="$(swift build --show-bin-path)"
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(rg --files Sources/MrMcLean -g '*.swift')
swiftc -parse-as-library -D UI_SMOKE -I "$BIN_DIR/Modules" \
    "${SOURCES[@]}" Scripts/ui-smoke.swift "$BIN_DIR"/MrMcLeanCore.build/*.o \
    -o "$BIN_DIR/MrMcLeanUISmoke"
exec "$BIN_DIR/MrMcLeanUISmoke" "$@"
