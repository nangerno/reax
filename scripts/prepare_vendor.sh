#!/usr/bin/env bash
# Copy the patched reax-engine tree into dm-all/vendor for the Docker build context.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENG="$(cd "$ROOT/../reax-engine" && pwd)"
DEST="$ROOT/vendor"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$ENG/engine" "$DEST/engine"
cp -a "$ENG/docker/vllm-readout/entrypoint.sh" "$DEST/vllm-entrypoint.sh"
cp -a "$ENG/LICENSE" "$DEST/LICENSE"
cp -a "$ENG/NOTICE" "$DEST/NOTICE"
# Ensure colo-fast preset is present
grep -q 'colo-fast' "$DEST/engine/backends/vllm_readout.py"
echo "vendor ready from $ENG ($(cd "$ENG" && git rev-parse --short HEAD))"
