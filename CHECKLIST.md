# Pre-submit checklist (dm-all / Engine v2.0)

## Scaffold validity (this repo)

- [x] UDS `/health` + `/internal/v1/decide` + token auth
- [x] Competitive image based on reax-engine PR9 + `colo-fast` / `fp8-kv-colo`
- [x] Local blink eval: **1.278×**, composite **~1.084** (≥ 1.0765 margin) — preview only
- [x] Label `ai.reax.engine.models=blink` (vision/mammoth/reax1/jeffan undeclared = 1.0×)
- [ ] Rebuild with **real** `ai.reax.engine.hotkey=<your ss58>`
- [ ] Push to ghcr.io/docker.io/quay.io and re-run `reax-engine-eval` on clean refs
- [ ] On-chain `reax-eng/1:dm-all:…` before Fri 30 Oct 14:30 UTC slot (2 confirmations)
## Artifact

- [ ] Submission is a **Docker image**, not `model.safetensors` / GGUF / HF weights
- [ ] Image pushed to **ghcr.io**, **docker.io**, or **quay.io**
- [ ] Compressed manifest size **≤ 15 GB**
- [ ] Image name short enough that `reax-eng/1:dm-all:<image>@sha256:<digest>` ≤ **128 bytes**
- [ ] Label `ai.reax.engine.hotkey=<ss58>` matches the hotkey that will commit
- [ ] Label `ai.reax.engine.models` is correct (`all` / omit / explicit slots) — no typos
- [ ] If reusing another entry’s code/binaries: `ai.reax.engine.parents` declared
- [ ] No weight blobs in the image (Option A from Fri 30 Oct crown)

## Contract

- [x] Serves `GET /health` and `POST /internal/v1/decide` on `$RUNTIME_UDS`
- [x] Auth via `X-S1M-Internal-Token` from `$S1M_INTERNAL_TOKEN_FILE`
- [ ] Reads weights only from `/model` (`$PLUMB_MODEL_DIR`); `HF_HUB_OFFLINE=1` (**real** backend)
- [ ] Honours `$REAX_MODEL` for every declared slot (**real** backend)
- [x] Vision path accepts `images` (one picture) when serving Blink
- [x] No network needed at runtime (`--network none`)
- [x] Does **not** cache answers by state/question (anti-cache probes)
- [x] Exact prefix reuse OK; answer tables / oracle calls are not

## Local measure

- [ ] `reax-engine-eval --track dm-all --candidate <pin> --weights …` passes gates
- [ ] Composite score clears ~**+7.65%** margin (v20 noise) if you intend to challenge
- [ ] Each declared slot clears its no-regression floor and memory budget

## Chain + award

- [ ] Hotkey registered on **netuid 92** (competition UID; separate from serving if you want both)
- [ ] Commitment published: `reax-eng/1:dm-all:…`
- [ ] Source under **MIT or Apache-2.0** (incl. GPU kernels) ready for award approval
- [ ] Waiting for review (`REVIEWED/<digest>`) + Option A `weights_ok` (needed from Fri 30 Oct crown)
- [ ] Crowning only at **Tue/Fri 14:30 UTC** after 2 confirmations

## Do not confuse with

| Competition | What you upload |
|---|---|
| **Engine v2 `dm-all`** (this folder) | Docker **engine** image |
| Specialist / generalist tracks | HF model `repo@revision` |
| Ingot / other weight contests | Quantized weight files (GGUF, etc.) |
| Serving (`reax-s1`) | Runtime sidecar + on-chain inference commitment |
