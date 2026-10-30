#!/usr/bin/env bash
# Finish submit for wallet uyj / hotkey hk92-01 after docker login.
# Usage:
#   docker login                # or: echo $TOKEN | docker login ghcr.io -u USER --password-stdin
#   IMAGE=uyj/e ./scripts/submit_hk92.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SS58=5F9hGoJmvPrRCgw2zpHQqnUZ9Kfjb9VTn5RkvDKU93p7MCKM
: "${IMAGE:?set IMAGE to a short name on an allowed registry, e.g. uyj/e or ghcr.io/YOU/e}"
TAG="${TAG:-dm-all}"
SRC="${SRC:-local/e:dm-all-submit}"

# Verify local image labels
MODELS=$(docker image inspect "$SRC" --format '{{index .Config.Labels "ai.reax.engine.models"}}')
HK=$(docker image inspect "$SRC" --format '{{index .Config.Labels "ai.reax.engine.hotkey"}}')
echo "source=$SRC models=$MODELS hotkey=$HK"
[[ "$HK" == "$SS58" ]] || { echo "ERROR: image hotkey label != hk92-01 ss58"; exit 1; }
[[ "$MODELS" == "blink,jeffan" || "$MODELS" == "blink" ]] || echo "WARN: unexpected models label $MODELS"

docker tag "$SRC" "${IMAGE}:${TAG}"
echo "==> pushing ${IMAGE}:${TAG}"
docker push "${IMAGE}:${TAG}"

DIGEST=$(docker buildx imagetools inspect "${IMAGE}:${TAG}" --format '{{.Manifest.Digest}}' 2>/dev/null || true)
DIGEST="${DIGEST#sha256:}"
if [[ ! "$DIGEST" =~ ^[0-9a-f]{64}$ ]]; then
  DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE}:${TAG}" | awk -F@ '{print $2}')
  DIGEST="${DIGEST#sha256:}"
fi
[[ "$DIGEST" =~ ^[0-9a-f]{64}$ ]] || { echo "could not resolve digest"; exit 1; }

PIN="${IMAGE}@sha256:${DIGEST}"
# Prefer short form without docker.io/ prefix when on hub
PIN="${PIN#docker.io/}"
COMMIT="reax-eng/1:dm-all:${PIN}"
BYTES=$(printf '%s' "$COMMIT" | wc -c)
echo "commit ($BYTES/128): $COMMIT"
(( BYTES <= 128 )) || { echo "commitment too long — shorten IMAGE"; exit 1; }

printf '%s\n' "$PIN" > "$ROOT/.last_pin"
printf '%s\n' "$COMMIT" > "$ROOT/.last_commitment"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN=1 — not writing chain"
  reax-commit --wallet-name uyj --wallet-hotkey hk92-01 set --dry-run "$COMMIT"
  exit 0
fi

reax-commit --wallet-name uyj --wallet-hotkey hk92-01 set "$COMMIT"
reax-commit --wallet-name uyj --wallet-hotkey hk92-01 show
echo "submitted."
