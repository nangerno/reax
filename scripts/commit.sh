#!/usr/bin/env bash
# Publish the on-chain commitment for dm-all.
#
# Note: ``reax-engine-submit --track`` currently only lists v1 tracks (s1-fast).
# For dm-all use ``reax-commit set`` with the full element string (same write path).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT="${1:-}"
if [[ -z "$COMMIT" && -f "$ROOT/.last_commitment" ]]; then
  COMMIT="$(cat "$ROOT/.last_commitment")"
fi
: "${COMMIT:?usage: scripts/commit.sh 'reax-eng/1:dm-all:<image>@sha256:<digest>'}"

if [[ "$COMMIT" != reax-eng/1:dm-all:*@sha256:* ]]; then
  echo "expected reax-eng/1:dm-all:<image>@sha256:<64 hex>"
  exit 1
fi

BYTES=$(printf '%s' "$COMMIT" | wc -c)
echo "commitment ($BYTES bytes): $COMMIT"
if (( BYTES > 128 )); then
  echo "ERROR: exceeds 128-byte chain limit"
  exit 1
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN=1 — not writing to chain"
  echo "would run: reax-commit set $(printf %q "$COMMIT")"
  exit 0
fi

# Keeps any existing inference element on the same hotkey unless REPLACE_ALL=1.
ARGS=()
if [[ "${REPLACE_ALL:-0}" == "1" ]]; then
  ARGS+=(--replace-all)
fi

reax-commit set "$COMMIT" "${ARGS[@]}"
echo "published. Crowning slots: Tue & Fri 14:30 UTC. First dm-all crown: Fri 30 Oct 2026 14:30Z."
