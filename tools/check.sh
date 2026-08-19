#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

lua tests/store_test.lua
lua tests/payload_test.lua
lua tests/format_test.lua

if command -v rojo-doctor >/dev/null; then
	rojo-doctor check
fi
