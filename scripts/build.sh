#!/usr/bin/env bash
# Build + push a dm-all candidate image pinned by digest.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${HOTKEY:?set HOTKEY=<ss58 of the committing hotkey>}"
: "${IMAGE:?set IMAGE=ghcr.io/you/eng  (short name; ~37 chars max)}"
TAG="${TAG:-dm-all}"
MODELS="${MODELS:-all}"   # all | mammoth,blink,reax1,jeffan,vision

echo "==> building $IMAGE:$TAG (hotkey=$HOTKEY models=$MODELS)"
docker build \
  --label "ai.reax.engine.hotkey=${HOTKEY}" \
  --label "ai.reax.engine.models=${MODELS}" \
  -t "${IMAGE}:${TAG}" \
  .

echo "==> pushing ${IMAGE}:${TAG}"
docker push "${IMAGE}:${TAG}"

DIGEST="$(docker buildx imagetools inspect "${IMAGE}:${TAG}" --format '{{.Manifest.Digest}}' 2>/dev/null \
  || docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE}:${TAG}" | awk -F@ '{print $2}')"
DIGEST="${DIGEST#sha256:}"
if [[ ! "$DIGEST" =~ ^[0-9a-f]{64}$ ]]; then
  echo "could not resolve a 64-hex digest; after push run:"
  echo "  docker buildx imagetools inspect ${IMAGE}:${TAG}"
  exit 1
fi

PIN="${IMAGE}@sha256:${DIGEST}"
COMMIT="reax-eng/1:dm-all:${PIN}"
BYTES=$(printf '%s' "$COMMIT" | wc -c)
echo
echo "pinned:  $PIN"
echo "commit:  $COMMIT"
echo "bytes:   $BYTES / 128"
if (( BYTES > 128 )); then
  echo "ERROR: commitment exceeds 128 bytes — shorten IMAGE"
  exit 1
fi
echo "$PIN" > "$ROOT/.last_pin"
echo "$COMMIT" > "$ROOT/.last_commitment"
echo
echo "next: scripts/eval.sh   then   scripts/commit.sh"
