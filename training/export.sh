#!/usr/bin/env bash
# Turn a trained adapter into a model Yapperroni loads, on this Mac.
#
#   ./export.sh <adapter>  [name]
#     adapter: a checkpoints/.../adapter folder, hf:you/repo (pulls the best
#              checkpoint), or "base" for unmodified turbo (the round-trip test)
#     name:    default yapperroni-turbo
#
# Produces ggml-<name>-q5_0.bin and ggml-<name>-encoder.mlmodelc — whisper.cpp
# strips the -q5_0 suffix when it looks for the encoder, so the two names must
# match exactly — and copies both into Yapperroni's support folder, where the
# model pickers list them.
set -euo pipefail

ADAPTER="${1:?usage: ./export.sh <adapter|hf:repo|base> [name]}"
NAME="${2:-yapperroni-turbo}"
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$T/../vendor-whisper"
OUT="$T/out/$NAME"
SUPPORT="$HOME/Library/Application Support/Yapperroni"
PY="$T/.venv-export/bin/python"

# coremltools pins its own torch range, so export gets its own environment.
if [ ! -x "$PY" ]; then
  echo "==> creating export environment (first run only)"
  uv venv -q "$T/.venv-export" --python 3.12
  uv pip install -q --python "$PY" -r "$T/requirements-export.txt"
fi
# convert-h5-to-ggml.py reads the mel filter bank from OpenAI's repo.
if [ ! -d "$T/.cache/openai-whisper" ]; then
  git clone -q --depth 1 https://github.com/openai/whisper.git "$T/.cache/openai-whisper"
fi

mkdir -p "$OUT"
echo "==> merging adapter"
(cd "$T" && "$PY" merge.py --adapter "$ADAPTER" --out "$OUT/hf")

echo "==> converting to whisper.cpp format"
"$PY" "$W/models/convert-h5-to-ggml.py" "$OUT/hf" "$T/.cache/openai-whisper" "$OUT" >/dev/null

echo "==> quantizing to q5_0"
"$W/build-mac-coreml/bin/whisper-quantize" "$OUT/ggml-model.bin" "$OUT/ggml-$NAME-q5_0.bin" q5_0 >/dev/null
rm -f "$OUT/ggml-model.bin"

echo "==> building the Neural Engine encoder (several minutes)"
# The converter only accepts OpenAI's architecture names; ours is renamed after.
ARCH=large-v3-turbo
# Same recipe as the published encoders — fp16 and the Neural-Engine layout
# (--optimize-ane). Without it the encoder is numerically different: stock
# turbo through it scored 8.4% on the Duflo lecture against 7.6% for the
# published one. With it, the round trip is word-for-word identical. The
# converter's help calls --optimize-ane "currently broken"; it is not, here.
(cd "$W" && "$PY" models/convert-h5-to-coreml.py --model-name "$ARCH" --model-path "$OUT/hf" \
   --encoder-only True --quantize True --optimize-ane True >/dev/null)
# Compiled by coremltools rather than `xcrun coremlc`, which needs the full
# Xcode app; Command Line Tools alone do not ship it.
rm -rf "$OUT/ggml-$NAME-encoder.mlmodelc"
"$PY" - "$W/models/coreml-encoder-$ARCH.mlpackage" "$OUT/ggml-$NAME-encoder.mlmodelc" <<'PYEOF'
import shutil, sys
import coremltools as ct
# CPU_ONLY fails to compile the Neural-Engine layout; ALL compiles it.
m = ct.models.MLModel(sys.argv[1], compute_units=ct.ComputeUnit.ALL)
shutil.copytree(m.get_compiled_model_path(), sys.argv[2])
PYEOF
rm -rf "$W/models/coreml-encoder-$ARCH.mlpackage" "$W/models/hf-$ARCH.pt"

echo "==> installing into $SUPPORT"
cp "$OUT/ggml-$NAME-q5_0.bin" "$SUPPORT/"
rm -rf "$SUPPORT/ggml-$NAME-encoder.mlmodelc"
cp -R "$OUT/ggml-$NAME-encoder.mlmodelc" "$SUPPORT/"
du -sh "$SUPPORT/ggml-$NAME-q5_0.bin" "$SUPPORT/ggml-$NAME-encoder.mlmodelc"
echo
echo "done. Check it:"
echo "  /Applications/Yapperroni.app/Contents/MacOS/Yapperroni --selftest-whisper $W/samples/jfk.wav ggml-$NAME-q5_0.bin"
echo "Then pick it in Modes → Room or Call → Model."
