# REAX Engine v2.0 dm-all competitive candidate.
# Declares: mammoth,blink,reax1,jeffan (vision omitted = 1.0x; avoids eager/graph conflict).
#
# Build from /root/dm-all (engine sources pulled from sibling ../reax-engine):
#   HOTKEY=<ss58> docker build \
#     --build-arg HOTKEY=$HOTKEY \
#     --build-arg GIT_SHA=$(cd ../reax-engine && git rev-parse --short HEAD) \
#     -t ghcr.io/YOU/e:dm-all .
#
# Speed levers vs published refs:
#   blink  → preset colo-fast (util 0.52, 128 seqs, 16k batch, BI on)
#   jeffan → preset fp8-kv-colo (no BI; calibrated ~1.04x, gate-safe)
#   mammoth/reax1 → native production_opts + REAX_MAX_WAIT_MS=4

ARG VLLM_BASE=vllm/vllm-openai@sha256:8a69ffad015f138d7170c4ddc429e230a3bc1c1719f67e14324749df200a4b90
FROM ${VLLM_BASE}

ARG HOTKEY=REPLACE_ME
ARG GIT_SHA=unknown
ARG MODELS=mammoth,blink,reax1,jeffan

LABEL org.opencontainers.image.title="reax-dm-all" \
      org.opencontainers.image.description="REAX Engine v2.0 dm-all candidate (faster colo presets)" \
      org.opencontainers.image.source="https://github.com/reaxlabs/reax-engine" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.licenses="LicenseRef-REAX-Engine-1.1 AND Apache-2.0 AND MIT" \
      ai.reax.engine.hotkey="${HOTKEY}" \
      ai.reax.engine.models="${MODELS}" \
      ai.reax.engine.commit="${GIT_SHA}"

ENV HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 VLLM_NO_USAGE_STATS=1 DO_NOT_TRACK=1 HF_HUB_DISABLE_TELEMETRY=1 \
    PYTHONPATH=/opt/reax PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 OPENAI_API_KEY= \
    PLUMB_MODEL_DIR=/model REAX_MODEL_DIR=/model REAX_VLLM_PORT=8000 \
    REAX_MAX_WAIT_MS=4 CIE_LAZY_LOAD=1 \
    HOME=/tmp VLLM_CACHE_ROOT=/tmp/vllm-cache TRITON_CACHE_DIR=/tmp/triton \
    TORCHINDUCTOR_CACHE_DIR=/tmp/inductor XDG_CACHE_HOME=/tmp/.cache NUMBA_CACHE_DIR=/tmp/numba \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1

# Native Qwen path (mammoth / reax-1) needs fla + pinned transformers; vLLM image already has torch/CUDA.
RUN python3 -m pip install --break-system-packages -q \
      "transformers==5.17.0" "accelerate==1.15.0" "safetensors==0.8.0" \
      "flash-linear-attention==0.5.2" "kernels==0.16.1" "einops==0.8.2" \
      "uvicorn==0.29.0" "uvloop==0.22.1" "httptools==0.8.0" \
 || python3 -m pip install -q \
      "transformers==5.17.0" "accelerate==1.15.0" "safetensors==0.8.0" \
      "flash-linear-attention==0.5.2" "kernels==0.16.1" "einops==0.8.2" \
      "uvicorn==0.29.0" "uvloop==0.22.1" "httptools==0.8.0"

RUN mkdir -p /opt/reax /licenses

# Engine sources: build context includes a `vendor/` tree (see scripts/prepare_vendor.sh).
COPY vendor/engine /opt/reax/engine
COPY vendor/vllm-entrypoint.sh /opt/reax/vllm-entrypoint.sh
COPY entrypoint.sh /opt/reax/entrypoint.sh
COPY LICENSE /licenses/LICENSE.dm-all
COPY vendor/LICENSE /licenses/LICENSE.reax-engine
COPY vendor/NOTICE /licenses/NOTICE

# Mount points must exist in the image: the competition runs --read-only so Docker cannot create them.
RUN chmod +x /opt/reax/entrypoint.sh /opt/reax/vllm-entrypoint.sh \
 && mkdir -p /opt/reax/fla-configs/rtx-pro-6000-blackwell-server \
             /opt/reax/fla-configs/rtx-pro-6000-blackwell \
             /run/reax \
 && python3 -m compileall -q /opt/reax/engine \
 && useradd --uid 10002 --create-home --home-dir /home/engine engine || true

USER 10002:10002
WORKDIR /opt/reax

HEALTHCHECK --interval=30s --timeout=5s --start-period=1800s --retries=3 CMD \
  if [ -n "$RUNTIME_UDS" ]; then curl -sf --unix-socket "$RUNTIME_UDS" http://localhost/health; \
  else curl -sf "http://127.0.0.1:${REAX_PORT:-8741}/health"; fi || exit 1

ENTRYPOINT ["/opt/reax/entrypoint.sh"]
