#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   GODOT=/path/to/godot ./tools/run_ci.sh
#   ./tools/run_ci.sh /path/to/godot

GODOT_BIN="${1:-${GODOT:-}}"
PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_SCENE="res://scenes/Main.tscn"

if [[ -z "${GODOT_BIN}" ]]; then
  echo "Godot executable not set. Pass as first arg or set GODOT env var." >&2
  exit 2
fi

if [[ ! -f "${GODOT_BIN}" ]]; then
  echo "Godot executable not found at: ${GODOT_BIN}" >&2
  exit 2
fi

echo ""
echo "=== Import pass (warm cache) ==="
"${GODOT_BIN}" --headless --quit --path "${PROJECT_PATH}" --import

echo ""
echo "=== Script + scene load check ==="
"${GODOT_BIN}" --headless --path "${PROJECT_PATH}" -s res://tools/ci/check_resources.gd

echo ""
echo "=== Run main scene (headless smoke test) ==="
"${GODOT_BIN}" --headless --quit --path "${PROJECT_PATH}" "${MAIN_SCENE}"

echo ""
echo "=== Start Day button (headless smoke test) ==="
"${GODOT_BIN}" --headless --path "${PROJECT_PATH}" -s res://tools/ci/smoke_start_day.gd

echo ""
echo "All CI checks passed."





