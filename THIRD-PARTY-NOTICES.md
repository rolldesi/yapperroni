# Third-party notices

Yapperroni is MIT licensed, and so is everything it builds on. Nothing here
imposes a condition beyond preserving these notices.

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

## Apple frameworks

AVFoundation, AppKit, SwiftUI, Metal, Accelerate and Carbon are used under the
Apple SDK license as system frameworks. They are linked, not redistributed.
