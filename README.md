# REAX Engine v2.0 — `dm-all` competitive candidate

Open engine track on Bittensor SN92. Goal: beat pinned references on the decisionmodels.io lineup; composite margin under `v20` ≈ **+7.65%**. First crowning: **Fri 30 Oct 2026, 14:30 UTC**.

## Local measurement (this box, 29 Oct)

Blink-only probe against a mountpoint-fixed copy of `ref-blink` on RTX PRO 6000:

| Slot | Ratio | Mean dist | Top agree | Mem MiB | Gate |
|---|---|---|---|---|---|
| **blink** | **1.278×** | 0.027 (≤0.08) | 99.8% (≥97%) | 48 549 (≤52 224) | **PASS** |

Composite with only `blink` declared (others = 1.0×): **S ≈ 1.084 ≥ 1.0765** → clears the challenge margin in this local preview.

Speed lever: vLLM preset `colo-fast` (BI on, util 0.52, 128 seqs, 16k batch tokens, 4k context) vs reference `ref-prod` (util 0.45, 32 seqs).

> Local ≠ validator verdict (no `runsc`, item seed differs, refs were rebuilt with empty `/run/reax` + fla mountpoints for sysbox). Re-measure on a clean host before committing.

## What this image is

- Based on **reax-engine PR #9** (`vendor/`) + competitive presets.
- Entrypoint routes `REAX_MODEL` → native (mammoth/reax1) or vLLM (blink/jeffan).
- **Recommended label for first crown:** `ai.reax.engine.models=blink` (measured).
- Vision intentionally omitted (same `REAX_MODEL` as blink; eager vs graphs conflict).

## Build & measure

```bash
# needs sibling ../reax-engine on branch pr-9 with colo-fast preset
HOTKEY=<ss58> IMAGE=ghcr.io/YOU/e MODELS=blink ./scripts/crown_build.sh
docker push "$IMAGE:dm-all"

# stage official HF pins under /data/weights/{blink,jeffan,mammoth,reax1}
# copy fla-configs to a path Docker can bind (avoid /root under sysbox):
cp -a ../reax-subnet/runtimes/s1-fast/fla-configs /data/fla-configs

export REAX_ENGINE_FLA_CONFIG_ROOT=/data/fla-configs
CAND=ghcr.io/YOU/e@sha256:... \
  W_BLINK=/data/weights/blink \
  ./scripts/eval.sh   # or scripts/eval_local.sh with MODELS=blink
```

Commitment:

```text
reax-eng/1:dm-all:<image>@sha256:<digest>   # ≤ 128 bytes
```

Publish with `scripts/commit.sh` (or `reax-commit set`). Crowning: Tue/Fri 14:30 UTC after 2 confirmations + review + Option A.

## Licence

MIT for this folder’s glue. Engine code from reax-engine remains under the REAX Engine License; award needs MIT/Apache-2.0 source publication of your changes.
