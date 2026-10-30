#!/bin/bash
# dm-all competitive entrypoint: route by $REAX_MODEL to native (mammoth/reax1) or vLLM (blink/jeffan).
# Faster-than-reference presets are selected unless REAX_PROFILE=reference.
set -euo pipefail

MODEL=${REAX_MODEL:?set REAX_MODEL}
DIR=${PLUMB_MODEL_DIR:-${REAX_MODEL_DIR:-/model}}
export PLUMB_MODEL_DIR="$DIR"
export REAX_MODEL_DIR="$DIR"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

case "$MODEL" in
  mammoth|mammoth-1)
    export REAX_MODEL=mammoth-1
    # Native Qwen stack: production opts + continuous-batch wait (reference uses 4 ms).
    export REAX_PROFILE="${REAX_PROFILE:-reference}"
    export REAX_MAX_WAIT_MS="${REAX_MAX_WAIT_MS:-4}"
    export CIE_LAZY_LOAD="${CIE_LAZY_LOAD:-1}"
    exec python -m engine.serve
    ;;
  reax1|reax-1)
    export REAX_MODEL=reax-1
    export REAX_PROFILE="${REAX_PROFILE:-reference}"
    export REAX_MAX_WAIT_MS="${REAX_MAX_WAIT_MS:-4}"
    export CIE_LAZY_LOAD="${CIE_LAZY_LOAD:-1}"
    exec python -m engine.serve
    ;;
  blink|blink-v0.3-26b-a4b|s1-fast-2)
    export REAX_MODEL=blink-v0.3-26b-a4b
    if [ "${REAX_PROFILE:-}" = reference ]; then
      export REAX_PRESET="${REAX_PRESET:-ref-prod}"
    else
      # Competitive: denser colo batching than ref-prod (see colo-fast preset).
      export REAX_PRESET="${REAX_PRESET:-colo-fast}"
      # Do NOT set enforce-eager: text blink ref uses CUDA graphs; vision is undeclared.
      unset REAX_VLLM_EXTRA || true
    fi
    exec /opt/reax/vllm-entrypoint.sh
    ;;
  jeffan|jeffan-31b-1710)
    export REAX_MODEL=jeffan-31b-1710
    if [ "${REAX_PROFILE:-}" = reference ]; then
      export REAX_PRESET="${REAX_PRESET:-fp8-kv-colo-bi}"
    else
      # Documented ~1.04x vs BI reference while clearing gates (engcomposite calibration).
      export REAX_PRESET="${REAX_PRESET:-fp8-kv-colo}"
    fi
    exec /opt/reax/vllm-entrypoint.sh
    ;;
  *)
    echo "dm-all: unsupported REAX_MODEL=$MODEL (declare only mammoth,blink,reax1,jeffan)" >&2
    exit 2
    ;;
esac
