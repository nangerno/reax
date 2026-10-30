#!/usr/bin/env bash
# Build + run the image under competition-like flags (hash backend, no GPU weights).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${TAG:-local/dm-all:smoke}"
WORKDIR="${WORKDIR:-/tmp/dm-all-docker-smoke}"

echo "==> docker build $TAG"
docker build \
  --label "ai.reax.engine.hotkey=${HOTKEY:-5LocalSmokeHotkeyNotForChain00001}" \
  --label "ai.reax.engine.models=${MODELS:-all}" \
  -t "$TAG" \
  "$ROOT"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/io" "$WORKDIR/model"
chmod 777 "$WORKDIR/io" "$WORKDIR/model"
printf 'dockertok' > "$WORKDIR/io/token"
chmod 666 "$WORKDIR/io/token"

docker rm -f dm-all-smoke >/dev/null 2>&1 || true
docker run -d --name dm-all-smoke --network none --read-only \
  --user 10002:10002 \
  --cap-drop ALL --security-opt no-new-privileges \
  -e REAX_MODEL="${REAX_MODEL:-mammoth-1}" \
  -e ENGINE_BACKEND=hash \
  -e RUNTIME_UDS=/run/reax/engine.sock \
  -e S1M_INTERNAL_TOKEN_FILE=/run/reax/token \
  -e PLUMB_MODEL_DIR=/model \
  -v "$WORKDIR/model:/model:ro" \
  -v "$WORKDIR/io:/run/reax" \
  --tmpfs /tmp:rw,exec,nosuid,nodev,size=1g \
  "$TAG" >/dev/null

cleanup() { docker rm -f dm-all-smoke >/dev/null 2>&1 || true; }
trap cleanup EXIT

for _ in $(seq 1 50); do
  [[ -S "$WORKDIR/io/engine.sock" ]] && break
  sleep 0.1
done
[[ -S "$WORKDIR/io/engine.sock" ]] || { docker logs dm-all-smoke; exit 1; }

python - <<PY
import asyncio
from aiohttp import ClientSession, UnixConnector
sock = "$WORKDIR/io/engine.sock"
async def main():
    conn = UnixConnector(path=sock)
    async with ClientSession(connector=conn) as s:
        async with s.get("http://localhost/health") as r:
            assert r.status == 200 and (await r.json())["ok"]
        body = {"state": "docker-smoke", "questions": {"q": {
            "type": "choice", "instructions": "x",
            "criteria": {"a": "A", "b": "B"},
        }}}
        headers = {"X-S1M-Internal-Token": "dockertok"}
        async with s.post("http://localhost/internal/v1/decide", json=body, headers=headers) as r:
            data = await r.json()
            assert r.status == 200, data
            assert "probabilities" in data["answers"]["q"]
    print("DOCKER_SMOKE_PASS")
asyncio.run(main())
PY
