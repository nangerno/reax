#!/usr/bin/env bash
# Build the competitive dm-all image pinned by digest.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${HOTKEY:?set HOTKEY=<ss58 of committing hotkey>}"
: "${IMAGE:?set IMAGE=ghcr.io/you/e  (short; ~37 chars max)}"
TAG="${TAG:-dm-all}"
MODELS="${MODELS:-mammoth,blink,reax1,jeffan}"

"$ROOT/scripts/prepare_vendor.sh"
GIT_SHA="$(cd "$ROOT/../reax-engine" && git rev-parse --short HEAD)"

echo "==> building $IMAGE:$TAG models=$MODELS"
docker build \
  --build-arg "HOTKEY=${HOTKEY}" \
  --build-arg "GIT_SHA=${GIT_SHA}" \
  --build-arg "MODELS=${MODELS}" \
  -t "${IMAGE}:${TAG}" \
  .

echo "==> resolving digest (local)"
DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE}:${TAG}" 2>/dev/null | awk -F@ '{print $2}' || true)"
if [[ -z "$DIGEST" || "$DIGEST" != sha256:* ]]; then
  # unpushed local image: hash the image id config as a stand-in reminder to push
  DIGEST="sha256:$(docker image inspect --format='{{.Id}}' "${IMAGE}:${TAG}" | sed 's/^sha256://')"
  echo "NOTE: push to a registry before commit; local id=$DIGEST"
fi
DIGEST="${DIGEST#sha256:}"
PIN="${IMAGE}@sha256:${DIGEST}"
COMMIT="reax-eng/1:dm-all:${PIN}"
BYTES=$(printf '%s' "$COMMIT" | wc -c)
echo "pinned: $PIN"
echo "commit: $COMMIT ($BYTES / 128 bytes)"
(( BYTES <= 128 )) || { echo "ERROR: commitment too long"; exit 1; }
printf '%s\n' "$PIN" > "$ROOT/.last_pin"
printf '%s\n' "$COMMIT" > "$ROOT/.last_commitment"
echo "next: stage weights then scripts/eval.sh (or MODELS=blink for a fast probe)"
