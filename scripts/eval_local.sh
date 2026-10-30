#!/usr/bin/env bash
# Local dm-all measurement on this host (sysbox-safe paths under /data).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${CAND:?set CAND=localhost:5000/e@sha256:...}"
MODELS="${MODELS:-blink}"
OUT="${OUT:-$ROOT/eval-out/eval-$(date -u +%Y%m%dT%H%M%SZ).json}"
WORKDIR="${WORKDIR:-/tmp/reax-eng-work}"
export REAX_ENGINE_FLA_CONFIG_ROOT="${REAX_ENGINE_FLA_CONFIG_ROOT:-/data/fla-configs}"

REF_ARGS=()
[[ -n "${REF_BLINK:-}" ]] && REF_ARGS+=(--reference "blink=${REF_BLINK}")
[[ -n "${REF_JEFFAN:-}" ]] && REF_ARGS+=(--reference "jeffan=${REF_JEFFAN}")
[[ -n "${REF_MAMMOTH:-}" ]] && REF_ARGS+=(--reference "mammoth=${REF_MAMMOTH}")
[[ -n "${REF_REAX1:-}" ]] && REF_ARGS+=(--reference "reax1=${REF_REAX1}")
# If multiple --reference, engcli only accepts one string; join:
REF_JOIN=""
[[ -n "${REF_BLINK:-}" ]] && REF_JOIN+="blink=${REF_BLINK},"
[[ -n "${REF_JEFFAN:-}" ]] && REF_JOIN+="jeffan=${REF_JEFFAN},"
[[ -n "${REF_MAMMOTH:-}" ]] && REF_JOIN+="mammoth=${REF_MAMMOTH},"
[[ -n "${REF_REAX1:-}" ]] && REF_JOIN+="reax1=${REF_REAX1},"
REF_JOIN="${REF_JOIN%,}"

WEIGHTS="blink=/data/weights/blink,jeffan=/data/weights/jeffan,mammoth=/data/weights/mammoth,reax1=/data/weights/reax1"

mkdir -p "$(dirname "$OUT")" "$WORKDIR"
ARGS=(--track dm-all --candidate "$CAND" --weights "$WEIGHTS" --models "$MODELS"
      --no-pull --registries "ghcr.io,docker.io,quay.io,localhost:5000"
      --memory "${MEMORY:-80g}" --cpus "${CPUS:-16}" --workdir "$WORKDIR" --out "$OUT")
[[ -n "$REF_JOIN" ]] && ARGS+=(--reference "$REF_JOIN")

echo "==> reax-engine-eval ${ARGS[*]}"
exec reax-engine-eval "${ARGS[@]}"
