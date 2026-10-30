#!/usr/bin/env bash
# Local preview of the validator's dm-all measurement (no chain, no crowning).
# Needs the pinned HF weight snapshots on disk and an RTX-class GPU.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN="${1:-}"
if [[ -z "$PIN" && -f "$ROOT/.last_pin" ]]; then
  PIN="$(cat "$ROOT/.last_pin")"
fi
: "${PIN:?usage: scripts/eval.sh <image@sha256:digest>}"

# Stage the official pins (docs/ENGINE-COMPETITION-V2.md §10), then point these dirs at them.
: "${W_MAMMOTH:?set W_MAMMOTH=/path/to/baselabs/mammoth-1 snapshot}"
: "${W_BLINK:?set W_BLINK=/path/to/Blink-v0.3-26B-A4B-NVFP4 snapshot}"
: "${W_REAX1:?set W_REAX1=/path/to/decisionmodels/reax-1 snapshot}"
: "${W_JEFFAN:?set W_JEFFAN=/path/to/Jeffan-31b-1710 snapshot}"

# Optional: MODELS=mammoth  or  MODELS=blink,vision  (default: image label / all)
MODELS_ARGS=()
if [[ -n "${MODELS:-}" ]]; then
  MODELS_ARGS=(--models "$MODELS")
fi

OUT="${OUT:-$ROOT/eval-$(date -u +%Y%m%dT%H%M%SZ).json}"

echo "==> reax-engine-eval --track dm-all --candidate $PIN"
reax-engine-eval --track dm-all \
  --candidate "$PIN" \
  --weights "mammoth=${W_MAMMOTH},blink=${W_BLINK},reax1=${W_REAX1},jeffan=${W_JEFFAN}" \
  "${MODELS_ARGS[@]}" \
  --out "$OUT"

echo "wrote $OUT"
