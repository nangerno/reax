#!/usr/bin/env bash
# Local UDS contract smoke test (hash backend). No GPU, no HF weights, no chain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${WORKDIR:-/tmp/reax-dm-all-smoke}"
MODEL_ID="${REAX_MODEL:-mammoth-1}"
TOKEN="smoke-token-$(date +%s)"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/io" "$WORKDIR/model"
printf '%s' "$TOKEN" > "$WORKDIR/io/token"
SOCK="$WORKDIR/io/engine.sock"

export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
export REAX_MODEL="$MODEL_ID"
export RUNTIME_UDS="$SOCK"
export S1M_INTERNAL_TOKEN_FILE="$WORKDIR/io/token"
export PLUMB_MODEL_DIR="$WORKDIR/model"
export ENGINE_BACKEND=hash
export HF_HUB_OFFLINE=1

python -m engine.server &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }
trap cleanup EXIT

# Wait for socket
for _ in $(seq 1 50); do
  [[ -S "$SOCK" ]] && break
  sleep 0.1
done
[[ -S "$SOCK" ]] || { echo "socket not ready"; exit 1; }

python - <<PY
import asyncio, json, os, sys
from aiohttp import ClientSession, UnixConnector

sock = os.environ["RUNTIME_UDS"]
token = open(os.environ["S1M_INTERNAL_TOKEN_FILE"]).read().strip()
model = os.environ["REAX_MODEL"]

async def main():
    conn = UnixConnector(path=sock)
    async with ClientSession(connector=conn) as s:
        async with s.get("http://localhost/health") as r:
            assert r.status == 200, r.status
            h = await r.json()
            assert h.get("ok") is True, h
            print("health:", h)

        cases = [
            ("noul", {
                "type": "noul",
                "instructions": "Refund?",
                "criteria": {"true": "Yes", "false": "No"},
            }, None, {"type", "probabilities", "noul"}),
            ("choice", {
                "type": "choice",
                "instructions": "Mood?",
                "criteria": {"calm": "Quiet", "tense": "Suspense", "joyful": "Happy"},
            }, None, {"type", "probabilities", "choice", "confidence"}),
            ("score", {
                "type": "score",
                "instructions": "Severity?",
                "criteria": ["low", "medium", "high"],
            }, None, {"type", "probabilities", "score", "confidence", "legend"}),
            ("vision-choice", {
                "type": "choice",
                "instructions": "Largest colour?",
                "criteria": {"red": None, "blue": None, "green": None},
            }, ["data:image/png;base64,iVBORw0KGgo="], {"type", "probabilities", "choice", "confidence"}),
        ]

        for name, question, images, fields in cases:
            body = {
                "request_id": "smoke",
                "deadline_unix_ms": 9_999_999_999_999,
                "state": f"smoke-state-{name}",
                "questions": {"q1": question},
            }
            if images is not None:
                body["images"] = images
            headers = {"X-S1M-Internal-Token": token, "Content-Type": "application/json"}
            async with s.post("http://localhost/internal/v1/decide", json=body, headers=headers) as r:
                raw = await r.text()
                assert r.status == 200, (name, r.status, raw)
                data = json.loads(raw)
                ans = data["answers"]["q1"]
                assert set(ans) == fields, (name, set(ans), fields)
                probs = ans["probabilities"]
                assert abs(sum(probs.values()) - 1.0) < 1e-3, (name, probs)
                print(f"ok {name}: { {k: round(v,4) for k,v in probs.items()} }")

        # Auth must fail without token
        async with s.post(
            "http://localhost/internal/v1/decide",
            json={"state": "x", "questions": {"q": {"type": "noul", "instructions": "?", "criteria": {}}}},
            headers={"Content-Type": "application/json"},
        ) as r:
            assert r.status == 401, r.status
            print("ok unauthorized")

        # Anti-cache style: same state, different question → different distribution
        async def decide(instr):
            body = {
                "state": "shared-state",
                "questions": {"q": {
                    "type": "choice",
                    "instructions": instr,
                    "criteria": {"a": "A", "b": "B"},
                }},
            }
            headers = {"X-S1M-Internal-Token": token}
            async with s.post("http://localhost/internal/v1/decide", json=body, headers=headers) as r:
                return (await r.json())["answers"]["q"]["probabilities"]

        p1 = await decide("question-one")
        p2 = await decide("question-two")
        assert p1 != p2, "hash backend must depend on the question (anti-cache)"
        print("ok anti-cache dependency")

    print(f"SMOKE PASS model={model}")

asyncio.run(main())
PY
