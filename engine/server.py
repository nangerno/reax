"""REAX Engine v2.0 (`dm-all`) contract server.

Validators start this container with:

  REAX_MODEL=<model id>          # mammoth-1 | blink-v0.3-26b-a4b | reax-1 | jeffan-31b-1710
  RUNTIME_UDS=/run/reax/engine.sock
  S1M_INTERNAL_TOKEN_FILE=/run/reax/token
  PLUMB_MODEL_DIR=/model         # official frozen weights, read-only
  HF_HUB_OFFLINE=1

``ENGINE_BACKEND``:
  * ``hash`` (default in this scaffold) — deterministic hash logits for local
    contract / UDS smoke tests. Will fail real correctness gates vs the
    reference; never commit a hash-only image as a competitive entry.
  * ``real`` — load ``/model`` and run your faster kernels (replace RealBackend).

Wire format matches ``reax_subnet.s1contract`` / SidecarBackend (criteria keys,
normalize_answer fields).
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import math
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from aiohttp import web

# Slot label → REAX_MODEL id (docs/ENGINE-COMPETITION-V2.md, engcomposite._DEFAULT_SLOTS)
MODEL_IDS = {
    "mammoth": "mammoth-1",
    "blink": "blink-v0.3-26b-a4b",
    "vision": "blink-v0.3-26b-a4b",  # same engine; items carry one image
    "reax1": "reax-1",
    "jeffan": "jeffan-31b-1710",
}

# Slot temperatures used by distance gates (engcomposite); bake into softmax.
MODEL_TEMPERATURES = {
    "mammoth-1": 1.0,
    "blink-v0.3-26b-a4b": 1.3,
    "reax-1": 1.9754,
    "jeffan-31b-1710": 1.0,
}


def _token() -> str:
    path = os.environ.get("S1M_INTERNAL_TOKEN_FILE", "")
    if path and Path(path).is_file():
        return Path(path).read_text(encoding="ascii").strip()
    tok = os.environ.get("S1M_INTERNAL_TOKEN", "")
    if tok:
        return tok
    sys.exit("engine: set S1M_INTERNAL_TOKEN_FILE or S1M_INTERNAL_TOKEN")


def option_keys(question: dict) -> list[str]:
    """Option keys from the production wire format (``criteria``, not options/choices)."""
    qtype = question.get("type")
    criteria = question.get("criteria")
    if qtype == "noul":
        # noul may omit criteria or send {}; keys are always true/false
        if criteria is None:
            criteria = {}
        if not isinstance(criteria, dict) or set(criteria) - {"true", "false"}:
            raise ValueError("noul criteria must be {} or {true,false}")
        return ["true", "false"]
    if qtype == "choice":
        if not isinstance(criteria, dict) or not criteria:
            raise ValueError("choice requires non-empty criteria object")
        return list(criteria.keys())
    if qtype == "score":
        if not isinstance(criteria, list) or len(criteria) < 2:
            raise ValueError("score requires criteria list with ≥2 levels")
        return [str(i) for i in range(len(criteria))]
    raise ValueError(f"unsupported question type: {qtype!r}")


def build_answer(question: dict, logits: list[float], temperature: float) -> dict[str, Any]:
    """Softmax + derived fields matching ``s1contract.normalize_answer`` / ``check_answer``."""
    keys = option_keys(question)
    if len(logits) != len(keys):
        raise ValueError(f"logits length {len(logits)} != n_options {len(keys)}")
    t = max(float(temperature), 1e-6)
    m = max(logits)
    exps = [math.exp((x - m) / t) for x in logits]
    s = math.fsum(exps) or 1.0
    probs = {k: e / s for k, e in zip(keys, exps)}
    qtype = question["type"]
    answer: dict[str, Any] = {"type": qtype, "probabilities": probs}
    if qtype == "noul":
        answer["noul"] = probs["true"]
    elif qtype == "choice":
        best = max(keys, key=lambda k: probs[k])
        answer["choice"] = best
        answer["confidence"] = probs[best]
    else:
        criteria = question["criteria"]
        answer["score"] = math.fsum(i * probs[str(i)] for i in range(len(criteria)))
        answer["confidence"] = max(probs.values())
        answer["legend"] = {str(i): criteria[i] for i in range(len(criteria))}
    return answer


class Backend:
    """Load ``/model`` for ``REAX_MODEL`` and return letter logits for one decision."""

    def __init__(self, model_id: str, model_dir: Path) -> None:
        self.model_id = model_id
        self.model_dir = model_dir

    def logits(self, state: Any, question: dict, images: list | None) -> list[float]:
        raise NotImplementedError


class HashBackend(Backend):
    """Deterministic pseudo-model for contract smoke tests (same idea as S1HashBackend)."""

    def __init__(self, model_id: str, model_dir: Path, salt: str = "scaffold") -> None:
        super().__init__(model_id, model_dir)
        self.salt = salt
        # Weights dir must exist in the competition sandbox; create is not allowed under /model (ro).
        if not model_dir.is_dir():
            sys.exit(f"engine: weights directory missing: {model_dir}")
        print(f"engine hash: model={model_id} weights={model_dir} salt={salt}", flush=True)

    def logits(self, state: Any, question: dict, images: list | None) -> list[float]:
        keys = option_keys(question)
        payload = [state, {"type": question.get("type"), "instructions": question.get("instructions"),
                           "criteria": question.get("criteria")}]
        if images:
            payload.append(list(images))
        base = json.dumps(payload, sort_keys=True, ensure_ascii=False)
        out: list[float] = []
        for k in keys:
            h = hashlib.sha256(f"{self.salt}\x00{base}\x00{k}".encode()).digest()
            out.append(int.from_bytes(h[:4], "big") / 2**32 * 12.0)
        return out


class RealBackend(Backend):
    """Replace ``logits`` with your faster engine before competing."""

    def __init__(self, model_id: str, model_dir: Path) -> None:
        super().__init__(model_id, model_dir)
        if not model_dir.is_dir():
            sys.exit(f"engine: weights directory missing: {model_dir}")
        # TODO: load tokenizer + weights from model_dir (offline).
        # TODO: capture CUDA graphs / warm kernels as needed for your stack.
        print(f"engine real (stub): model={model_id} weights={model_dir}", flush=True)

    def logits(self, state: Any, question: dict, images: list | None) -> list[float]:
        keys = option_keys(question)
        raise NotImplementedError(
            "RealBackend.logits is not implemented — replace with a real engine "
            f"for {self.model_id} before reax-engine-eval / on-chain submit "
            f"(n_options={len(keys)}, has_image={bool(images)})"
        )


def make_backend(model_id: str, model_dir: Path) -> Backend:
    mode = os.environ.get("ENGINE_BACKEND", "hash").strip().lower()
    if mode in ("hash", "scaffold", "test"):
        return HashBackend(model_id, model_dir, salt=os.environ.get("ENGINE_HASH_SALT", "scaffold"))
    if mode in ("real", "prod", "gpu"):
        return RealBackend(model_id, model_dir)
    sys.exit(f"engine: unknown ENGINE_BACKEND={mode!r} (use hash|real)")


def make_app(backend: Backend, token: str, temperature: float) -> web.Application:
    pool = ThreadPoolExecutor(max_workers=int(os.environ.get("ENGINE_WORKERS", "8")))

    async def health(_: web.Request) -> web.Response:
        return web.json_response({
            "ok": True,
            "model": backend.model_id,
            "backend": type(backend).__name__,
        })

    async def decide(request: web.Request) -> web.Response:
        got = request.headers.get("X-S1M-Internal-Token", "")
        if not hmac.compare_digest(got, token):
            return web.json_response({"error": "unauthorized"}, status=401)
        try:
            body = await request.json()
            (qid, question), = body["questions"].items()
            state = body["state"]
            images = body.get("images")
            if images is not None:
                if not isinstance(images, list) or len(images) != 1 or not isinstance(images[0], str):
                    raise ValueError("images must be a list of exactly one data URL")
        except Exception as exc:  # noqa: BLE001
            return web.json_response({"error": f"bad request: {type(exc).__name__}: {exc}"}, status=400)
        try:
            loop = asyncio.get_running_loop()
            raw = await loop.run_in_executor(pool, backend.logits, state, question, images)
            answer = build_answer(question, raw, temperature)
        except NotImplementedError as exc:
            return web.json_response({"error": str(exc)}, status=501)
        except Exception as exc:  # noqa: BLE001
            return web.json_response({"error": f"{type(exc).__name__}: {exc}"}, status=400)
        return web.json_response({"answers": {qid: answer}})

    app = web.Application(client_max_size=32 << 20)
    app.router.add_get("/health", health)
    app.router.add_post("/internal/v1/decide", decide)
    app["executor"] = pool
    return app


async def _serve() -> None:
    model_id = os.environ.get("REAX_MODEL", "").strip()
    if not model_id:
        sys.exit("engine: REAX_MODEL is required (mammoth-1 | blink-v0.3-26b-a4b | reax-1 | jeffan-31b-1710)")
    if model_id not in set(MODEL_IDS.values()):
        print(f"engine: warning: unexpected REAX_MODEL={model_id!r}", flush=True)

    uds = os.environ.get("RUNTIME_UDS", "")
    if not uds:
        sys.exit("engine: RUNTIME_UDS is required in the competition sandbox")

    model_dir = Path(os.environ.get("PLUMB_MODEL_DIR", "/model"))
    token = _token()
    backend = make_backend(model_id, model_dir)
    temp = float(os.environ.get(
        "REAX_ENGINE_TEMPERATURE",
        str(MODEL_TEMPERATURES.get(model_id, 1.0)),
    ))

    app = make_app(backend, token, temperature=temp)
    runner = web.AppRunner(app, access_log=None)
    await runner.setup()
    # Ensure parent exists when testing locally; competition mounts /run/reax.
    Path(uds).parent.mkdir(parents=True, exist_ok=True)
    if Path(uds).exists():
        Path(uds).unlink()
    await web.UnixSite(runner, uds).start()
    os.chmod(uds, 0o666)
    print(json.dumps({
        "ready": True,
        "model": model_id,
        "uds": uds,
        "backend": type(backend).__name__,
        "temperature": temp,
    }), flush=True)
    try:
        await asyncio.Event().wait()
    finally:
        app["executor"].shutdown(wait=False)


def main() -> None:
    asyncio.run(_serve())


if __name__ == "__main__":
    main()
