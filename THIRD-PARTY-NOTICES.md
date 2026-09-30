# Third-party notices

Yapperroni is MIT licensed. Everything it builds on is MIT or Apache-2.0, and
the optional NeMo models are CC-BY-4.0. Nothing here imposes a condition beyond
preserving these notices and crediting the model authors.

## whisper.cpp — MIT

Copyright (c) 2023-2026 The ggml authors
<https://github.com/ggml-org/whisper.cpp>

Provides the inference engine and the ggml tensor library. Cloned and compiled
by `build.sh`; the resulting static libraries are linked into the app binary.
Not redistributed as source in this repository.

## OpenAI Whisper model weights — MIT

Copyright (c) 2022 OpenAI
<https://github.com/openai/whisper>

`ggml-small.en-q5_1.bin` is the `small.en` model converted to GGML format and
quantized to q5_1, downloaded from
<https://huggingface.co/ggerganov/whisper.cpp>. Shipped inside the app bundle
and therefore redistributed in release DMGs.

## sherpa-onnx — Apache-2.0

Copyright (c) 2022-2026 Xiaomi Corporation and the k2-fsa authors
<https://github.com/k2-fsa/sherpa-onnx>

Runs the NeMo models. `build.sh` downloads the prebuilt macOS dylib and its C
header; `libsherpa-onnx-c-api.dylib` ships in `Contents/Frameworks` and is
therefore redistributed in release DMGs.

## ONNX Runtime — MIT

Copyright (c) Microsoft Corporation
<https://github.com/microsoft/onnxruntime>

`libonnxruntime.dylib`, bundled alongside sherpa-onnx.

## Optional models — not bundled

Fetched into Application Support by `YAPPERRONI_FETCH_MODELS=1 ./build.sh`,
never shipped inside the app:

- `ggml-large-v3-turbo-q5_0.bin` — OpenAI Whisper large-v3-turbo, MIT.
- Parakeet TDT 0.6B v3 — NVIDIA, CC-BY-4.0, ONNX export by sherpa-onnx.
  <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3>
- Canary 180M Flash — NVIDIA, CC-BY-4.0, ONNX export by sherpa-onnx.
  <https://huggingface.co/nvidia/canary-180m-flash>

## Apple frameworks

AVFoundation, AppKit, SwiftUI, Metal, Accelerate and Carbon are used under the
Apple SDK license as system frameworks. They are linked, not redistributed.
