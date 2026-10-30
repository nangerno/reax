"""Contract unit tests — no GPU, no Docker. Run: python -m pytest tests/ -q"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from engine.server import HashBackend, build_answer, option_keys  # noqa: E402


def test_option_keys_noul_empty():
    assert option_keys({"type": "noul"}) == ["true", "false"]
    assert option_keys({"type": "noul", "criteria": {}}) == ["true", "false"]


def test_option_keys_choice_uses_criteria_not_options():
    q = {"type": "choice", "criteria": {"calm": "Quiet", "tense": "Suspense"}}
    assert option_keys(q) == ["calm", "tense"]
    with pytest.raises(ValueError):
        option_keys({"type": "choice", "options": ["a", "b"]})


def test_option_keys_score_list():
    q = {"type": "score", "criteria": ["low", "mid", "high"]}
    assert option_keys(q) == ["0", "1", "2"]


def test_build_answer_choice_fields():
    q = {"type": "choice", "criteria": {"a": "A", "b": "B", "c": "C"}}
    ans = build_answer(q, [0.0, 5.0, 1.0], temperature=1.0)
    assert set(ans) == {"type", "probabilities", "choice", "confidence"}
    assert ans["choice"] == "b"
    assert abs(ans["confidence"] - ans["probabilities"]["b"]) < 1e-9
    assert abs(sum(ans["probabilities"].values()) - 1.0) < 1e-6


def test_build_answer_noul_fields():
    q = {"type": "noul", "criteria": {"true": "Yes", "false": "No"}}
    ans = build_answer(q, [2.0, 0.0], temperature=1.0)
    assert set(ans) == {"type", "probabilities", "noul"}
    assert abs(ans["noul"] - ans["probabilities"]["true"]) < 1e-9
    assert abs(ans["probabilities"]["true"] + ans["probabilities"]["false"] - 1.0) < 1e-6


def test_build_answer_score_fields():
    q = {"type": "score", "criteria": ["bad", "ok", "good"]}
    ans = build_answer(q, [0.0, 0.0, 3.0], temperature=1.0)
    assert set(ans) == {"type", "probabilities", "score", "confidence", "legend"}
    assert ans["legend"] == {"0": "bad", "1": "ok", "2": "good"}
    expected = sum(i * ans["probabilities"][str(i)] for i in range(3))
    assert abs(ans["score"] - expected) < 1e-6
    assert abs(ans["confidence"] - max(ans["probabilities"].values())) < 1e-9


def test_hash_backend_deterministic(tmp_path: Path):
    model_dir = tmp_path / "model"
    model_dir.mkdir()
    b = HashBackend("mammoth-1", model_dir)
    q = {"type": "choice", "instructions": "mood?", "criteria": {"calm": "c", "tense": "t"}}
    a = b.logits("state-1", q, None)
    b2 = b.logits("state-1", q, None)
    assert a == b2
    # different question → different logits (anti-cache property of hash)
    q2 = {"type": "choice", "instructions": "other?", "criteria": {"calm": "c", "tense": "t"}}
    assert b.logits("state-1", q2, None) != a


def test_hash_backend_sees_images(tmp_path: Path):
    model_dir = tmp_path / "model"
    model_dir.mkdir()
    b = HashBackend("blink-v0.3-26b-a4b", model_dir)
    q = {"type": "choice", "instructions": "colour?", "criteria": {"red": None, "blue": None}}
    img = ["data:image/png;base64,aaa"]
    z0 = b.logits("s", q, None)
    z1 = b.logits("s", q, img)
    assert z0 != z1


def test_softmax_temperature_changes_mass():
    q = {"type": "choice", "criteria": {"a": "A", "b": "B"}}
    cold = build_answer(q, [0.0, 2.0], temperature=0.5)
    hot = build_answer(q, [0.0, 2.0], temperature=2.0)
    assert cold["probabilities"]["b"] > hot["probabilities"]["b"]
    assert math.isfinite(cold["confidence"])
