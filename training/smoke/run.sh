#!/usr/bin/env bash
# The whole pipeline on whisper-tiny and ~120 real AMI rows, in a few minutes:
# label prefixes, the restore pass, training, a hard kill mid-run, resume, and
# the epoch rollover. Run after any change to the training code.
set -euo pipefail
T="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$T"
PY=.venv/bin/python
[ -x "$PY" ] || { uv venv -q .venv --python 3.12 && uv pip install -q --python "$PY" -r requirements.txt nbformat; }

$PY text.py | tail -1
$PY smoke/check_labels.py | tail -1
$PY smoke/make_fixtures.py | tail -1
F=smoke/fixtures
L="ami_ihm=$F/ami_ihm.parquet,ami_sdm=$F/ami_sdm.parquet,vox_en=$F/vox_en.parquet,vox_fr=$F/vox_fr.parquet"
L="$L,vox_french_accent=$F/vox_french_accent.parquet,ami_far_field=$F/ami_far_field.parquet,earnings22_calls=$F/earnings22_calls.parquet"
S=runs/smoke
rm -rf "$S"
quiet() { grep -v -i "warn\|loading weights\|shuffle buffer" || true; }

echo "== prepare"
$PY prepare.py --store $S --model openai/whisper-tiny --local "$L" --flush 40 --batch 8 2>&1 | quiet | tail -3

echo "== train, then kill -9 after the first timed save"
# Long enough that a timed save lands before the kill and the mix runs out
# and rolls into a second epoch — bf16 on Apple GPUs made 60 steps too quick
# for either.
ARGS=(--store $S --model openai/whisper-tiny --local "$L" --batch 4 --accum 1 --max-steps 150
      --eval-every 50 --eval-n 8 --save-minutes 0.1 --warmup 5
      --mix ami_sdm=1,ami_ihm=1,vox_en=1,vox_fr=1)  # even: an epoch ends when the rarest source runs out
$PY train.py "${ARGS[@]}" > runs/smoke-1.log 2>&1 &
PID=$!
for _ in $(seq 1 150); do grep -q "saved step [1-9][0-9]* (timer)" runs/smoke-1.log && break; sleep 2; done
kill -9 $PID 2>/dev/null || true
grep -o "saved step [0-9]* (timer)" runs/smoke-1.log | tail -1 || { echo "FAIL: no timed save before the kill"; exit 1; }

echo "== resume to the end"
$PY train.py "${ARGS[@]}" 2>&1 | quiet | grep -E "resumed|epoch|eval step|saved step" | tail -8
$PY - <<'EOF'
import json
m = json.load(open("runs/smoke/checkpoints/latest/meta.json"))
assert m["step"] == 150, f"stopped at step {m['step']}"
assert m["epoch"] >= 1, "never rolled over into a second epoch"
assert m["history"][0]["step"] == 0, "no step-0 baseline"
print(f"PASS — step {m['step']}, epoch {m['epoch']}, best mean WER {m['best']:.3f}")
EOF
