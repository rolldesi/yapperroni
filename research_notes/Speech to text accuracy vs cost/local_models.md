# Strongest Open-Weight / Locally-Runnable STT Models for Apple Silicon (16GB RAM), as of October 2026

**Scope:** NVIDIA Canary-Qwen-2.5B, Canary-1B-flash, Canary-1B v2, Parakeet TDT 0.6B v2/v3 (+ newly-found Nemotron-3.5-ASR-Streaming-0.6B); OpenAI Whisper large-v3, large-v3-turbo, distil-whisper; Mistral Voxtral Mini 3B, Voxtral Small 24B (+ its native-streaming sibling, found on the leaderboard as "Voxtral-Mini-4B-Realtime-2602"); IBM Granite Speech 3.3 8B (+ newer 3.3-2B and 4.0-1B-speech, found on the leaderboard; separately-reported-but-unverified 4.1-2B and 5.0 Turbo CTC); Kyutai STT 1B/2.6B; Microsoft Phi-4-multimodal; Moonshine (base/tiny + its "Streaming" tiny/small/medium siblings); Apple SpeechAnalyzer (macOS 26).

**Methodology notes (read before trusting any number below):**
- **Primary accuracy source:** I fetched the Hugging Face **Open ASR Leaderboard**'s backing data directly — `https://raw.githubusercontent.com/huggingface/open_asr_leaderboard/main/scripts/data/en_shortform.csv` — live on **2026-10-08** (the file's last GitHub commit is 2026-05-22; the repo's README separately references an eval pass dated 2026-07-24, so treat the data as a **~May–Jul 2026 snapshot, re-confirmed live on 2026-10-08**). This CSV is the leaderboard's actual evaluation harness output (independent, standardized methodology across all rows) and is the source for every Avg/AMI/TED-LIUM/RTFx number below unless marked otherwise. It directly resolved most of the "not found" gaps from an initial four-way parallel research pass (per-agent aggregator pulls disagreed or were incomplete; this single authoritative CSV supersedes them).
- A secondary source, arXiv:2510.06961v3 (the leaderboard's own paper, Oct 2026), was also consulted during initial research and is consistent with the CSV.
- Exact license names (Apache-2.0 / MIT / CC-BY-4.0, vs. the CSV's generic "Open"/"Proprietary" flag) and supported-language lists were independently verified against each model's own Hugging Face card, fetched live where noted.
- Every Apple Silicon **runtime** number (RTFx, memory, latency) in this report was measured on an **M2 Pro / M4 Pro / M5 Pro / unspecified Mac**, never on a literal MacBook Air. This is flagged inline as **(Pro-proxy)**. No source found in this research benchmarks any model on an actual Air — treat every "should work on an Air" statement as extrapolation, not measurement. The leaderboard CSV's own RTFx column is **GPU RTFx** (leaderboard eval infrastructure, not Apple Silicon) and is reported separately from Apple Silicon RTFx.
- Several Apple-Silicon-specific sources (soniqo.audio, aiindigo.com, promptquorum.com, developersdigest.tech) have the structural signature of programmatic/SEO content — used only where no primary source existed, tagged **(secondary, low-confidence)**.
- Every number is tagged **(vendor)**, **(independent)**, or **(leaderboard CSV, independent, live-pulled 2026-10-08)**. Any claim without an inline source link was excluded from Findings and moved to Gaps.

---

## Key Question 1: Which local model is most accurate on TED-LIUM (lecture) and AMI (far-field meeting), and by how much vs. Whisper large-v3-turbo?

### Takeaway
The answer splits by benchmark. On **TED-LIUM** (clean lecture audio), **NVIDIA Canary-Qwen-2.5B** is the most accurate in-scope model (2.71% vs. turbo's 3.57% — a **24.1% relative WER reduction**). On **AMI** (far-field, overlapping-speaker meeting audio), **IBM's Granite Speech family wins decisively**, not NVIDIA: the newer, much smaller **Granite Speech 4.0-1B** scores AMI 8.44% vs. turbo's 16.13% (a **47.7% relative reduction**, nearly double Canary-Qwen's AMI improvement), with Granite Speech 3.3-2B (8.90%) and 3.3-8B (8.98%) close behind. This is a materially different headline than a first pass of this research produced (which had missed Granite's AMI numbers and the newer 4.0-1B release entirely) — IBM's Granite Speech line, not NVIDIA's, is the best far-field/meeting performer among the task's named vendors.

### Cited Findings

**Master table** — all rows from the **Open ASR Leaderboard CSV, live-pulled 2026-10-08** unless noted; sorted by Avg WER ascending. Size = total parameters in billions, per the leaderboard's own size field (rounded, cross-checked against HF weight files where noted).

| Model | Avg WER | TED-LIUM WER | AMI WER | GPU RTFx | Size (B) | In scope? |
|---|---|---|---|---|---|---|
| CohereLabs/cohere-transcribe-03-2026 | 5.42 | 2.49 | 8.13 | 524.88 | 2 | Not in task's named vendors — flagged as context only |
| **ibm-granite/granite-4.0-1b-speech** | **5.52** | 3.10 | **8.44** | 280.02 | 2 | Newer Granite Speech release — in scope per "3.3 8B **or newer**" |
| nvidia/canary-qwen-2.5b | 5.63 | **2.71** | 10.19 | 418.28 | 2.5 | In scope |
| ibm-granite/granite-speech-3.3-8b | 5.74 | 3.40 | 8.98 | 145.42 | 9* | In scope (named model) |
| Qwen/Qwen3-ASR-1.7B | 5.76 | 2.28 | 10.56 | 147.93 | 1.7 | Not in task's named vendors |
| ibm-granite/granite-speech-3.3-2b | 6.00 | 3.57 | 8.90 | 270.57 | 3* | Scope-adjacent (smaller 3.3 sibling) |
| microsoft/Phi-4-multimodal-instruct | 6.02 | 2.94 | 11.09 | 151.1 | 6* | In scope — **current live number; supersedes a stale Mar-2025 self-reported 6.14%** |
| nvidia/parakeet-tdt-0.6b-v2 | 6.05 | 3.38 | 11.16 | 3,386.02 | 0.6 | In scope |
| nvidia/parakeet-tdt-0.6b-v3 | 6.32 | 2.80 | 11.39 | 3,332.74 | 0.6 | In scope |
| nvidia/canary-1b-flash | 6.35 | 3.12 | 13.11 | 1,045.75 | 1 | In scope |
| kyutai/stt-2.6b-en | 6.40 | 3.35 | 12.17 | 88.37 | 2.6 | In scope |
| nvidia/canary-1b (base, not flash/v2) | 6.50 | 3.56 | 13.90 | 235.34 | 1 | Related but not originally named |
| mistralai/Voxtral-Small-24B-2507 | 6.62 | 3.52 | 15.27 | 54.09 | 24 | In scope |
| usefulsensors/moonshine-streaming-medium | 6.66 | 2.98 | 10.68 | 448.15 | 0.245 | In scope |
| mistralai/Voxtral-Mini-3B-2507 | 7.05 | 3.68 | 16.30 | 109.86 | ~4.68† | In scope |
| nvidia/canary-1b-v2 | 7.15 | 4.29 | 16.01 | 749.00 | 1 | In scope |
| distil-whisper/distil-large-v3.5 | 7.21 | 3.64 | 14.63 | 202.03 | 0.8 | In scope |
| openai/whisper-large-v3 | 7.44 | 3.86 | 15.95 | 145.51 | 2 | In scope |
| mistralai/Voxtral-Mini-4B-Realtime-2602 | 7.68 | 3.79 | 17.07 | 93.32 | 4 | In scope — this is Mistral's **native-streaming** Voxtral variant |
| **openai/whisper-large-v3-turbo (baseline)** | **7.83** | **3.57** | **16.13** | 200.19 | 0.8 | In scope — comparison baseline |
| usefulsensors/moonshine-streaming-small | 7.84 | 3.77 | 12.53 | 566.33 | 0.123 | In scope |
| usefulsensors/moonshine-base | 9.99 | 5.65 | 17.49 | 565.97 | 0.0615 | In scope |
| usefulsensors/moonshine-streaming-tiny | 12.00 | 6.10 | 19.02 | 847.2 | 0.034 | In scope |
| usefulsensors/moonshine-tiny | 12.65 | 5.69 | 22.84 | 753.06 | 0.0271 | In scope |

\* IBM/Microsoft "size" fields in the leaderboard likely include encoder+adapter+LLM-backbone totals, not just the headline parameter count (e.g. Granite Speech "3.3-8b" lists as 9B total; Phi-4-multimodal as 6B total — both plausible given added speech encoders/adapters on top of the named backbone).
† Voxtral Mini 3B's HF-hosted weight files total **4.68B parameters / ~9.35GB at bf16** (summing the `model-00001-of-00002.safetensors` + `model-00002-of-00002.safetensors` shards; a third `consolidated.safetensors` file of near-identical size is an alternate single-file packaging of the *same* weights, not additional ones — the leaderboard's "5B" field appears to be a rounded-up total). [HF API blob listing](https://huggingface.co/api/models/mistralai/Voxtral-Mini-3B-2507?blobs=true), fetched live 2026-10-08.

No AMI/TED-LIUM/Avg numbers were found on the leaderboard for: **Apple SpeechAnalyzer** (closed, not submittable) or **Voxtral Mini Transcribe V2** (proprietary API-only, not locally runnable). **Granite Speech 4.1-2B and 5.0 Turbo CTC-470M**, mentioned in an independent 2026 blog review, do **not** appear in this live leaderboard CSV at all — treat their existence/accuracy as unverified pending a primary-source check.

**Source for the whole table:** [Open ASR Leaderboard CSV, live GitHub pull](https://raw.githubusercontent.com/huggingface/open_asr_leaderboard/main/scripts/data/en_shortform.csv) (independent, fetched 2026-10-08) / [repo](https://github.com/huggingface/open_asr_leaderboard) / cross-referenced with [arXiv 2510.06961v3](https://arxiv.org/html/2510.06961v3).

### Inferences
- If "most accurate" is read strictly against the task's literal model names (Canary-Qwen-2.5B, Granite Speech **3.3 8B**, Phi-4-multimodal, etc.), Canary-Qwen-2.5B wins TED-LIUM and Granite Speech 3.3-8B wins AMI among those exact models. If newer same-vendor releases count (which the task's own wording permits for Granite: "3.3 8B **or newer**"), Granite Speech 4.0-1B-speech is the single best all-around pick in this entire set for far-field audio, at a fraction of the size of the 8B model.
- Canary-1B v2's weaker English WER (worst AMI among the Canary/Parakeet set, 16.01%) is likely a multilingual-capacity trade-off — it supports far more languages (see Q2) than Canary-Qwen-2.5B, which is English-only.
- Parakeet TDT v2 edges out v3 on AMI/average because v2 is English-only while v3 spreads the same parameter budget across 25 languages — the usual monolingual-vs-multilingual accuracy tax.
- Moonshine Streaming Medium (245M params) posting AMI 10.68% / TED-LIUM 2.98% — beating Phi-4-multimodal (6B-class) and every Canary/Parakeet model except Canary-Qwen-2.5B on TED-LIUM, and beating all of them except the Granite family on AMI — is a notably strong accuracy-per-parameter result worth flagging given its tiny footprint (see Q2).

### Gaps
- Granite Speech 4.1-2B and 5.0 Turbo CTC-470M (named in one independent 2026 blog, [aiindigo.com](https://aiindigo.com/blog/granite-speech-4-1-2b-review-the-pragmatic-choice-for-edge-asr-in-2026) / [orcarouter.ai](https://www.orcarouter.ai/nl/blog/granite-speech-5-0-470m-turboctc-apache-explained)) are **not found on the live leaderboard CSV** under those names — only `granite-4.0-1b-speech` and the 3.3-family appear. Whether these are the same models under different version numbers, genuinely separate unlisted releases, or inaccurate blog claims could not be resolved in this research.
- Apple SpeechAnalyzer has no TED-LIUM/AMI numbers anywhere — it is a closed model not submittable to this leaderboard.
- No independent re-run or cross-validation of the leaderboard's own methodology was performed — all numbers trace to one evaluation harness; if that harness has systematic quirks (e.g., text normalization choices), they'd affect every row equally but could still bias absolute comparisons to truly independent evaluations.
- General caveat: one source ([hackernoon](https://hackernoon.com/we-used-benchmaxxers-favourite-trick-to-climb-10-places-on-the-hugging-face-open-asr-leaderboard)) describes gaming this specific leaderboard's ranking via eval-set-specific tricks, without naming a model — a reason not to over-read small rank differences.

---

## Key Question 2: Which can run in real time with streaming on an M-series Mac, through which runtime, and with what memory use?

### Takeaway
**Apple SpeechAnalyzer** is the only *OS-managed* option — true native streaming with a near-zero-app-footprint design on Apple Silicon — but it's a closed macOS 26 API, not an open-weight model. Among open-weight models, **Moonshine Streaming** (confirmed, real HF-hosted releases per the leaderboard entries above) and **Parakeet TDT via FluidAudio's CoreML port** both have confirmed native incremental-streaming modes with large compute headroom on Pro-class Apple Silicon. **Kyutai STT** and Mistral's **Voxtral-Mini-4B-Realtime-2602** are architecturally streaming-native too, but neither has any Apple Silicon benchmark or port found in this research. Everything else in scope (Canary family, Whisper family, Voxtral Mini/Small offline, Granite Speech, Phi-4-multimodal) is offline or chunked-pseudo-streaming only, and **Granite Speech and Phi-4-multimodal appear to have no Apple Silicon port of any kind** as of this research.

### Cited Findings

**Architecture: native streaming vs. offline/chunked**

| Model | Architecture | Source |
|---|---|---|
| Canary-Qwen-2.5B | Offline SALM (FastConformer encoder + Qwen3-1.7B decoder); max 40s/forward pass, needs external chunking for longer audio; **English-only** | (v) [model card](https://huggingface.co/nvidia/canary-qwen-2.5b), fetched live |
| Canary-1B-flash | Offline encoder-decoder; NeMo ships "chunked and streaming inference" scripts but this is buffered/chunked decoding, not cache-aware streaming; supports **4 languages (English, German, French, Spanish)** | (v) [NeMo docs](https://docs.nvidia.com/nemo/speech/nightly/asr/streaming_decoding/canary_chunked_and_streaming_decoding.html); [model card](https://huggingface.co/nvidia/canary-1b-flash), fetched live |
| Canary-1B v2 | Offline, same family; **25 languages** | (v) model card |
| Parakeet TDT 0.6B v2 | Offline/full-attention FastConformer-TDT by default, separate chunked long-form mode; **English-only** | (v) [model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) |
| Parakeet TDT 0.6B v3 | Same family; **25 languages** | (v) [model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) |
| **Nemotron-3.5-ASR-Streaming-0.6B** (new, not in original list, released 2026-06-04, not on the accuracy leaderboard) | Genuinely cache-aware streaming FastConformer + RNNT, selectable chunk size (80–1120ms) at inference time, **40 language-locales**, **OpenMDW-1.1 license (not CC-BY)** | (v) [model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) |
| Whisper large-v3 / large-v3-turbo | Offline/chunked (full attention over ~30s windows); **99 languages**; MIT license confirmed live | (i) [HF model card](https://huggingface.co/openai/whisper-large-v3-turbo), fetched live 2026-10-08 |
| distil-whisper/distil-large-v3.5 | Offline/chunked; **English-only**; MIT license ("inherits the MIT license from OpenAI's Whisper") | (v) [model card](https://huggingface.co/distil-whisper/distil-large-v3.5), fetched live |
| Voxtral Mini 3B / Small 24B (offline variants, 2507) | Offline/chunked audio-LLM (encoder + LLM backbone); both confirmed live to support the same **8 languages** (English, Spanish, French, Portuguese, Hindi, German, Dutch, Italian) — "natively multilingual" with automatic language detection; Apache-2.0 confirmed live for both | (v) [arXiv 2507.13264](https://arxiv.org/pdf/2507.13264); [Voxtral Mini model card](https://huggingface.co/mistralai/Voxtral-Mini-3B-2507); [Voxtral Small model card](https://huggingface.co/mistralai/Voxtral-Small-24B-2507), both fetched live |
| **Voxtral-Mini-4B-Realtime-2602** (Mistral's native-streaming variant, appears on the leaderboard — see Q1) | Genuinely native streaming per Mistral's own announcement ("Voxtral Transcribe 2" family), confirmed ~4B parameters, sub-200ms-latency configurable, Apache 2.0 | (v) [Mistral AI news](https://mistral.ai/news/voxtral-transcribe-2), 2026-02-04 |
| Granite Speech 3.3-8B / 3.3-2B | Offline, "two-pass design"; **5 ASR/transcription languages** (English, French, German, Spanish, Portuguese); Japanese and Mandarin are **speech-translation targets only**, not transcription languages; Apache-2.0 | (v) [IBM announcement](https://www.ibm.com/new/announcements/ibm-granite-3-3-speech-recognition-refined-reasoning-rag-loras); [model card](https://huggingface.co/ibm-granite/granite-speech-3.3-8b), fetched live |
| Granite Speech 4.0-1B-speech | Offline — a distinct, newer hybrid architecture from 3.3: 16-block CTC-trained conformer encoder + a 2-layer window-query transformer projector + Granite-4.0-1b-base LLM backbone (not a simple two-pass concatenation); supports **6 languages** (English, French, German, Spanish, Portuguese, Japanese); **Apache-2.0, confirmed live 2026-10-08**; 2B total params (BF16), exact weight-file GB not stated on the card | (v) [model card](https://huggingface.co/ibm-granite/granite-4.0-1b-speech), fetched live 2026-10-08 |
| Kyutai STT 1B-en_fr / 2.6B-en | Native streaming, Moshi-derived multistream architecture, confirmed via quote: *"unlike offline speech-to-text, where the model needs the entire audio... our model starts to output the transcript as soon as a few seconds of audio become available"*; 1B ≈0.5s delay + semantic VAD, 2.6B ≈2.5s delay tuned for accuracy; 2.6B-en is **English-only**, 1B is **English+French**; **CC-BY-4.0 confirmed live** | (v) [HF stt-2.6b-en model card](https://huggingface.co/kyutai/stt-2.6b-en), fetched live 2026-10-08 |
| Phi-4-multimodal | Offline, ~6B total params per leaderboard; no streaming mode documented; speech/audio modality covers **8 languages** (English, Chinese, German, French, Italian, Japanese, Spanish, Portuguese) | (v) [model card](https://huggingface.co/microsoft/Phi-4-multimodal-instruct), fetched live |
| Moonshine tiny (27M) / base (61.5M) | Processes variable-length audio directly (no 30s padding like Whisper); offered in both **English-only and multilingual** variants per the model's own spec table; official interface is segment-based | (v) [model card](https://huggingface.co/UsefulSensors/moonshine), fetched live |
| **Moonshine Streaming** (tiny/small/medium) | Confirmed real HF-hosted releases (`usefulsensors/moonshine-streaming-{tiny,small,medium}`) appearing on the live leaderboard itself — native streaming, lightweight 50Hz frontend + sliding-window Transformer encoder with cached state | (v/i) confirmed via [leaderboard CSV](https://raw.githubusercontent.com/huggingface/open_asr_leaderboard/main/scripts/data/en_shortform.csv) entries + [vendor docs](https://www.mintlify.com/moonshine-ai/moonshine/models/benchmarks) (the latter a Mintlify-hosted mirror, not necessarily the primary site) |
| Apple SpeechAnalyzer | Native streaming via `AsyncStream<AnalyzerInput>`, sub-200ms partial-result latency, fully on-device, no network call; exact supported-language list **not independently confirmed** (Apple's developer documentation page returned no readable content in this research) | (i) [Apple dev forums writeup](https://developer.apple.com/forums/thread/819555) |

**Apple Silicon runtime measurements found (all Pro/Studio-proxy except one ambiguous data point)**

| Model | Runtime | Device | RTFx / RTF | Peak memory | Streaming? | Date | Source |
|---|---|---|---|---|---|---|---|
| Parakeet TDT v3 (en) | FluidAudio (CoreML/ANE) | M4 Pro **(Pro-proxy)** | 155.6–237x (offline) | not reported | offline mode shown | n/d | (v) [FluidAudio benchmarks](https://docs.fluidinference.com/reference/benchmarks.md) |
| Parakeet TDT v2 (en) | FluidAudio (CoreML/ANE) | M4 Pro **(Pro-proxy)** | 145.8x (offline) | not reported | offline | n/d | (v) same |
| Parakeet-EOU streaming | FluidAudio (CoreML/ANE) | "Apple M2 (2022)" **(ambiguous — may be Air, unconfirmed)** | 4.78–12.48x, chunk-size dependent | not reported | **yes, native incremental, 640ms chunks** | macOS 26 era | (v) same |
| Parakeet (generic) | Swift CoreML / PyTorch MPS / PyTorch CPU | unspecified | — | 1.50 / 1.54 / 4.85 GB respectively | — | n/d | (i, secondary) [localai.io](https://localai.io/blog/parakeet-cpp-asr-on-cpu/) |
| WhisperKit large-v3-turbo | CoreML (Argmax) | M5 Pro **(Pro-proxy)** | RTF 0.084 → ~11.9x | 0.4 GB | chunk/VAD-triggered SSE streaming, not token-incremental | ~2026 | (secondary, low-confidence) [soniqo.audio](https://soniqo.audio/benchmarks) |
| whisper.cpp (Tiny–Medium), Metal | Metal | M1–M5 family, exact SKU unspecified | 20–65x | not reported | offline/chunked only | n/d | (secondary, low-confidence) [promptquorum.com](https://www.promptquorum.com/local-llms/apple-silicon-whisper-metal-benchmark) |
| whisper.cpp large-v3 (Q5_1), CoreML encoder | CoreML | M2 Pro **(Pro-proxy)** | ~5–7x | not reported | offline/chunked | n/d | (secondary, mentioned secondhand in community discussion — not independently re-verified) |
| Canary-Qwen-2.5B (community MLX port) | MLX | M5 Pro **(Pro-proxy)** | RTF 0.0674 → ~14.8x | not reported | explicitly offline | n/d | [HF Santosh-bold/canary-speechlm-mlx](https://huggingface.co/Santosh-bold/canary-speechlm-mlx) (very recent/unverified community port) |
| Voxtral Mini 3B, MLX FP16 | MLX | M5 Pro **(Pro-proxy)** | RTF 0.1305 → ~7.7x | 9.09 GB RSS | offline (whole-utterance tested) | ~Jul 2026 | (secondary) [soniqo.audio/guides/voxtral](https://soniqo.audio/guides/voxtral) |
| Voxtral Mini 3B, MLX INT8 | MLX | M5 Pro **(Pro-proxy)** | RTF 0.0906 → ~11x | 5.49 GB RSS | offline | ~Jul 2026 | same |
| Voxtral Mini 3B, MLX INT5 (default) | MLX | M5 Pro **(Pro-proxy)** | RTF 0.0739 → ~13.5x | 4.04 GB RSS | offline | ~Jul 2026 | same |
| Moonshine Streaming Tiny/Small/Medium | official streaming encoder | "recent MacBook Pro" **(Pro-proxy, vendor-vague)** | 34 / 73 / 107 ms per-chunk latency | not reported | **yes, native streaming** | n/d | (v) [vendor docs mirror](https://www.mintlify.com/moonshine-ai/moonshine/models/benchmarks) |
| Apple SpeechAnalyzer | native macOS 26 API | M2 Pro **(Pro-proxy)** | ~3x faster than Whisper **Small** (not turbo) — no RTF published | ~50–80 MB (lives outside app's own memory space; OS-managed, on-demand asset download) | streaming by design | Jul 2026 | (secondary, low-confidence) [developersdigest.tech](https://www.developersdigest.tech/blog/apple-speechanalyzer-vs-whisper-benchmark) |
| parakeet-mlx (senstella) | MLX | unspecified | no numbers in README | not reported | has `transcribe_stream` API; defaults to 120s chunks | n/d | [GitHub senstella/parakeet-mlx](https://github.com/senstella/parakeet-mlx) |
| sherpa-onnx (any Parakeet/Moonshine/Canary export) | ONNX Runtime | macOS supported (arm64 confirmed) | not found | not found | unclear if CoreML/ANE-accelerated on macOS, or CPU-only | n/d | insufficient primary-source data |
| mlx-whisper (Apple MLX team's own Whisper port) | MLX | — | not found | not found | offline/chunked | n/d | **not searched in this research — explicit gap** |

**Size / 16GB-feasibility flags**

| Model | fp16 size | Quantized options found | 16GB feasibility |
|---|---|---|---|
| Canary-Qwen-2.5B | ~2.4 GB bf16 (measured via HF API) | n/a found | Comfortable |
| Canary-1B-flash / Canary-1B v2 | ~1.8–2 GB estimated (not directly measured) | n/a found | Comfortable (inference) |
| Parakeet TDT v2/v3 | ~627 MB measured | n/a found | Very comfortable |
| Nemotron-3.5-ASR-Streaming-0.6B | ~638 MB measured | n/a found | Very comfortable, but no Mac port found |
| Whisper large-v3 / turbo / distil-whisper | ~3 GB / ~1.6 GB / smaller | widely available 4-/8-bit GGUF & CoreML | Comfortable |
| Voxtral Mini 3B | **~9.35 GB bf16** (corrected — 4.68B params, verified via HF blob listing) | 8-bit=5GB, 4-bit mixed=3.2GB (HF repo); separately MLX FP16=9.09GB RSS, INT8=5.49GB RSS, INT5=4.04GB RSS (measured, Pro-proxy) | Comfortable, especially at INT8/INT5; even fp16 (~9GB) is workable on 16GB with headroom for a lighter app, though INT5 is the safer choice |
| **Voxtral Small 24B** | ~48.5 GB bf16/f16 | Q4_K_M GGUF=14.3GB, Q5_K_M=17.1GB, Q6_K=19.9GB, Q8_0=25.8GB, MLX 8-bit=25GB | **Flagged infeasible-to-marginal on 16GB** — even the smallest quant found leaves ~1.7GB headroom before KV-cache/activations/app overhead |
| Granite Speech 3.3-8B | not directly found; analogous Granite 3.x 8B text LLMs run 16.1–16.4GB f16, ~3.06–3.2GB at Q2_K | no speech-specific GGUF/MLX artifact found | **Unresolved** — estimate only |
| Granite Speech 3.3-2B | not found | not found | Likely far more 16GB-friendly than the 8B given smaller size, but unverified |
| Granite Speech 4.0-1B-speech | 2B total params (BF16) per model card; exact GB not stated — **~4GB bf16 is a straightforward estimate (2B × 2 bytes), not independently confirmed** | no GGUF/MLX artifact found | Very comfortable if the ~4GB estimate holds, but unverified and no Apple Silicon port found |
| Kyutai STT 1B/2.6B | not found | not found | Likely comfortable given small param count, but unverified |
| Phi-4-multimodal (~6B per leaderboard) | not directly found | no Apple Silicon port found at all | Unresolved — no evidence anyone has run it on Mac |
| Moonshine (tiny 27.1M / streaming-tiny 34M / streaming-small 123M / base 61.5M / streaming-medium 245M, per CSV) | ~54MB–490MB estimated at fp16 (param count × 2 bytes; not independently measured as weight files) | n/a (already tiny) | Very comfortable across the whole family |

**Runtime/port licenses (distinct from the model's own license):**
- FluidAudio SDK (Swift, CoreML Parakeet wrapper): Apache 2.0 — confirmed via GitHub. [github.com/FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio)
- WhisperKit (Argmax): MIT — confirmed via HF model card. [huggingface.co/argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml)
- parakeet-mlx (senstella): Apache 2.0 — confirmed via GitHub README.
- whisper.cpp: MIT — well-established, not freshly re-verified this session.
- sherpa-onnx (k2-fsa): widely known as Apache 2.0 — not independently re-confirmed this session.

**Explicit verdict — can these do genuine 1:1 live transcription on a 16GB M-series MacBook Air?**
- **Best structural fit:** Apple SpeechAnalyzer — native OS streaming, tiny footprint lives outside the app process, macOS 26+/Apple Silicon only. Not open-weight / not redistributable, but it's the task's named "built-in local option" and the safest bet for 1:1 live captioning on an Air specifically.
- **The one measurement that *may* actually be an Air:** FluidAudio's Parakeet-EOU streaming benchmark device is logged only as "Apple M2 (2022)" — this could be a base M2 MacBook Air (which launched 2022) rather than an M2 Pro machine, but the source doesn't disambiguate. If it is an Air, it shows **4.78–12.48x RTFx even in native streaming mode (640ms chunks)** — comfortably above the 1.0x real-time bar. Treat this as the single most encouraging (but unconfirmed) data point in this report, not as settled proof.
- **Likely yes on compute grounds, otherwise Pro-proxy only:** Parakeet TDT via FluidAudio's streaming mode and Moonshine Streaming (sub-110ms chunk latency, 34M–245M params, strong accuracy per Q1). Both have large headroom extrapolating down from Pro to base Air silicon, but nobody has measured this on an Air.
- **Probably yes, with a caveat on pipeline shape:** WhisperKit (Whisper large-v3-turbo CoreML) — fast (~12x RTFx on Pro) and light (0.4GB), but its "streaming" is VAD/chunk-triggered rather than continuous incremental.
- **Promising on paper, unverified on Mac:** Kyutai STT and Voxtral-Mini-4B-Realtime-2602 — both architecturally the right design (native streaming, CC-BY-4.0 / Apache-2.0) but zero Apple Silicon benchmark found for either in this research.
- **Not currently streaming-capable as deployed on Mac:** Canary-Qwen-2.5B, Canary-1B-flash/v2, Parakeet TDT (offline mode), Whisper/turbo/distil-whisper, Voxtral Mini/Small (offline tested), Granite Speech (all variants), Phi-4-multimodal. Nemotron-3.5-ASR-Streaming-0.6B is architecturally streaming-native but has **no known Apple Silicon port or benchmark** — unavailable on Mac today despite being the right shape on paper.

### Inferences
For a 16GB Mac, Canary-Qwen-2.5B and the Parakeet/Canary 1B-class models fit comfortably in RAM even unquantized; Parakeet 0.6B is the lightest/fastest NVIDIA option if genuine low-latency streaming isn't a hard requirement. If true streaming is required, Apple SpeechAnalyzer is the pragmatic built-in answer for an Air today; among open-weight options, Moonshine Streaming (now confirmed as a real, accurate, tiny-footprint release per Q1) and Parakeet-via-FluidAudio are the best-evidenced candidates, pending an actual Air benchmark.

### Gaps
- **No benchmark found on a literal MacBook Air** for any model/runtime — the single largest gap in this research.
- WhisperKit's own ICML 2025 paper (arXiv:2507.10860) likely has exact per-device memory/latency tables; PDF extraction failed in this session.
- No Apple Silicon benchmark found for Kyutai STT, Granite Speech (any variant), or Phi-4-multimodal — these three appear to have **no known Apple Silicon runtime port** at all, not just "unbenchmarked."
- **mlx-whisper** (Apple's own MLX-team Whisper port) was never searched in this research — explicit gap, should be checked directly.
- sherpa-onnx's macOS acceleration backend (CoreML/ANE vs. CPU-bound ONNX) could not be confirmed; no RTFx or memory numbers surfaced for any model on it.
- No memory-pressure/swapping anecdotes found for any model running on an actual 16GB Mac alongside normal apps.
- Apple SpeechAnalyzer's exact supported-language list could not be retrieved (Apple's developer documentation page returned no parseable content).

---

## Key Question 3: Licensing constraints for a commercial app

### Takeaway
Every model in scope except one is commercially usable (Apache-2.0, MIT, or CC-BY-4.0). The one fully closed option is Mistral's **Voxtral Mini Transcribe V2** (API-only, not locally runnable — exclude from an on-device shortlist). One item needs a closer legal look: **Nemotron-3.5-ASR-Streaming-0.6B** uses NVIDIA's newer **OpenMDW-1.1** license (not the usual CC-BY-4.0), which permits commercial use but adds a patent/copyright-litigation termination clause.

### Cited Findings

| Model | License | Commercial use | Source |
|---|---|---|---|
| Canary-Qwen-2.5B | CC-BY-4.0 | Yes | (v) [model card](https://huggingface.co/nvidia/canary-qwen-2.5b) |
| Canary-1B-flash | CC-BY-4.0 | Yes | (v) [model card](https://huggingface.co/nvidia/canary-1b-flash) |
| Canary-1B v2 | CC-BY-4.0 | Yes | (v) [model card](https://huggingface.co/nvidia/canary-1b-v2) |
| Parakeet TDT 0.6B v2 | CC-BY-4.0 | Yes | (v) [model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) |
| Parakeet TDT 0.6B v3 | CC-BY-4.0 | Yes | (v) [model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) |
| Nemotron-3.5-ASR-Streaming-0.6B | **OpenMDW-1.1** (distinct from CC-BY) | Yes, but includes a patent/litigation termination clause — recommend legal review before shipping | (v) [model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) / [license text](https://openmdw.ai/license/1-1/) |
| Whisper large-v3 / large-v3-turbo | **MIT — confirmed live 2026-10-08** | Yes | (v) [HF model card](https://huggingface.co/openai/whisper-large-v3-turbo) |
| distil-whisper (all variants incl. large-v3.5) | **MIT — confirmed live** ("inherits the MIT license from OpenAI's Whisper") | Yes | (v) [model card](https://huggingface.co/distil-whisper/distil-large-v3.5) |
| Voxtral Mini 3B (2507) | Apache 2.0 | Yes | (v) [HF Voxtral-Mini-3B-2507](https://huggingface.co/mistralai/Voxtral-Mini-3B-2507) |
| Voxtral Small 24B (2507) | **Apache-2.0 — confirmed live 2026-10-08** (resolves a prior "needs verification" gap) | Yes | (v) [model card](https://huggingface.co/mistralai/Voxtral-Small-24B-2507) |
| Voxtral-Mini-4B-Realtime-2602 (native streaming) | Apache 2.0, confirmed explicitly | Yes | (v) [Mistral AI news](https://mistral.ai/news/voxtral-transcribe-2) |
| Voxtral Mini Transcribe V2 | Proprietary / API-only | **N/A — not open-weight, not locally runnable** | (v) same |
| Granite Speech 3.3-8B / 3.3-2B | Apache 2.0 | Yes | (v) [HF ibm-granite org](https://huggingface.co/ibm-granite) |
| Granite Speech 4.0-1B-speech | **Apache 2.0 — confirmed live 2026-10-08 on its own card** | Yes | (v) [model card](https://huggingface.co/ibm-granite/granite-4.0-1b-speech) |
| Kyutai STT 1B/2.6B | **CC-BY-4.0 — confirmed live 2026-10-08** directly from the model card | Yes, but attribution is a legal requirement, not just courtesy | (v) [HF kyutai/stt-2.6b-en](https://huggingface.co/kyutai/stt-2.6b-en) |
| Phi-4-multimodal-instruct | MIT | Yes | (v) [HF model card](https://huggingface.co/microsoft/Phi-4-multimodal-instruct) |
| Moonshine (all variants, incl. Streaming) | MIT | Yes | (v) [HF UsefulSensors/moonshine](https://huggingface.co/UsefulSensors/moonshine) |
| Apple SpeechAnalyzer | Not an open-weight license — governed by the standard Apple Developer Program / platform terms; no weights to redistribute, model is Apple's property, OS-managed | Yes for building commercial Mac apps that call the API; gated to macOS 26+/Apple Silicon, cannot extract/redistribute the model | (i) [Apple Developer Forums](https://developer.apple.com/forums/thread/818005) |

### Inferences
None of the in-scope models are "research-only" as the task brief worried might be the case — the risk is narrower: one non-standard license clause (Nemotron's OpenMDW-1.1).

### Gaps
Granite Speech 4.1-2B / 5.0 Turbo CTC's licenses were reported by a secondary blog as "Apache 2.0" but these models weren't independently located on the HF Hub or the leaderboard in this research — treat as unconfirmed pending direct verification.

---

## Key Question 4: Evidence on accented English and noisy audio

### Takeaway
NVIDIA publishes the strongest first-party noise/accent evidence in this set (Earnings-22 accented-speech WER + synthetic SNR-degradation curves for every Canary/Parakeet model, now cross-checked against the live leaderboard CSV's own Earnings22 column). A dedicated cross-model African-accented-English benchmark, **AfriSpeech-MultiBench** (arXiv:2511.14255, Nov 2025), independently evaluates Whisper, Distil-Whisper, Granite Speech 3.3-2B, Canary-Qwen-2.5B, and Voxtral — the best available apples-to-apples accent comparison found, though its full numeric table could not be extracted (PDF parsing failed). No reliable accent/noise evidence was found at all for Moonshine, Apple SpeechAnalyzer, or Phi-4-multimodal.

### Cited Findings

**Earnings-22 (accented, earnings-call speech) WER, from the same live leaderboard CSV as Q1 — (independent, leaderboard CSV, live-pulled 2026-10-08):**

| Model | Avg WER (clean) | Earnings-22 WER | Relative degradation |
|---|---|---|---|
| ibm-granite/granite-4.0-1b-speech | 5.52 | 8.48 | +53.6% |
| nvidia/canary-qwen-2.5b | 5.63 | 10.45 | +85.6% |
| ibm-granite/granite-speech-3.3-8b | 5.74 | 9.42 | +64.1% |
| ibm-granite/granite-speech-3.3-2b | 6.00 | 10.25 | +70.8% |
| microsoft/Phi-4-multimodal-instruct | 6.02 | 10.16 | +68.8% |
| nvidia/parakeet-tdt-0.6b-v2 | 6.05 | 11.15 | +84.3% |
| nvidia/parakeet-tdt-0.6b-v3 | 6.32 | 11.19 | +77.1% |
| nvidia/canary-1b-flash | 6.35 | 12.77 | +101.1% |
| kyutai/stt-2.6b-en | 6.40 | 10.99 | +71.7% |
| mistralai/Voxtral-Small-24B-2507 | 6.62 | 10.50 | +58.6% |
| mistralai/Voxtral-Mini-3B-2507 | 7.05 | 10.69 | +51.6% |
| nvidia/canary-1b-v2 | 7.15 | 11.79 | +64.9% |
| distil-whisper/distil-large-v3.5 | 7.21 | 11.29 | +56.6% |
| openai/whisper-large-v3 | 7.44 | 11.29 | +51.7% |
| mistralai/Voxtral-Mini-4B-Realtime-2602 | 7.68 | 11.84 | +54.2% |
| openai/whisper-large-v3-turbo | 7.83 | 11.63 | +48.5% |

Interestingly, **Granite Speech 4.0-1B-speech has both the best clean-average AND the best Earnings-22 (accented) WER among the whole in-scope set** — the smallest degradation in absolute terms, though not the smallest *relative* degradation (Voxtral Mini 3B and whisper-large-v3-turbo show smaller relative jumps, i.e. they degrade proportionally less even though their baseline is worse). Source for this whole table: [leaderboard CSV](https://raw.githubusercontent.com/huggingface/open_asr_leaderboard/main/scripts/data/en_shortform.csv).

**NVIDIA's own synthetic SNR-degradation curves (vendor, from individual model cards, same ~2026-05/07 snapshot):**
- Canary-Qwen-2.5B: 10dB→2.41%, 5dB→4.08%, 0dB→9.83%, −5dB→30.60%. [model card](https://huggingface.co/nvidia/canary-qwen-2.5b)
- Canary-1B-flash: −5dB→29.71%. [model card](https://huggingface.co/nvidia/canary-1b-flash)
- Canary-1B v2: 0dB SNR→5.08% vs 2.18% clean (LibriSpeech). [model card](https://huggingface.co/nvidia/canary-1b-v2)
- Parakeet TDT v2: **telephony 8kHz μ-law audio: 6.32% WER, only ~4.1% relative degradation from clean** — notably robust to telephone-quality audio. [model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
- Parakeet TDT v3: 0dB SNR→11.66%. [model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)

**Cross-model accented-English benchmark:**
- AfriSpeech-MultiBench (Nov 19, 2025) evaluates Whisper, Distil-Whisper, Granite Speech 3.3-2B, Canary-Qwen-2.5B, Voxtral (plus closed models GPT-4o transcribe, Gemini 2.0 Flash, Google Chirp 3, AWS/Azure) across multiple African countries/domains. On a reported SIL/Short/Int.SIL composite scale: Voxtral scored 43.51 avg ("mid-range," behind specialized systems like Intron-Sahara V2), Granite Speech 3.3-2B scored 45.86. [arXiv 2511.14255](https://arxiv.org/pdf/2511.14255) — **(independent; exact per-model full table not extracted, PDF text came back unparseable; a follow-up HTML fetch at arxiv.org/html/2511.14255 is recommended)**.

**Other model-specific evidence:**
- Mistral Voxtral: vendor claims accuracy is maintained "in challenging acoustic environments, such as factory floors, busy call centers, and field recordings" — no independent WER-under-noise table corroborates this beyond the Earnings-22 column above. (v) [Mistral Voxtral Transcribe 2 announcement](https://mistral.ai/news/voxtral-transcribe-2)
- Kyutai STT: only a general vendor claim of being "robust to noisy conditions" and handling audio up to 2 hours — no independent accent/noise-specific WER figure beyond the Earnings-22 column above. (v) [kyutai.org/stt](https://kyutai.org/stt)
- Whisper (version-unpinned, likely large-v2/v3 family): one independent writeup cites Scottish-accented WER of 18.18% vs. 4.75% on standard speech; a separate blog cites Australian-accented Whisper API WER of 18.21% vs. much lower on American English — both indicative of known Whisper accent sensitivity, **neither pinned to large-v3-turbo specifically.** (i, weak citations) [sky-scribe.com](https://www.sky-scribe.com/en/blog/ai-stt-accuracy-handling-noise-accents-and-jargon)
- Apple SpeechAnalyzer: one independent benchmark reports a clean-vs-noisy WER split of 2.12%/4.56% for SpeechAnalyzer vs. 3.74%/7.95% for **Whisper Small** (not large-v3-turbo, so not directly comparable to this report's main baseline). (secondary, low-confidence) [developersdigest.tech, Jul 2026](https://www.developersdigest.tech/blog/apple-speechanalyzer-vs-whisper-benchmark)
- Quantization effect on robustness: no source found comparing a quantized (CoreML/MLX) version of any model against its fp16 reference specifically on noisy or accented audio. The one fp16-vs-int8-vs-int5 comparison found (Voxtral Mini 3B on MLX: 4.633% / 4.578% / 4.744% WER respectively) was run on **clean** read speech only, and is itself from a low-confidence secondary source. (secondary, low-confidence) [soniqo.audio/guides/voxtral](https://soniqo.audio/guides/voxtral)

### Inferences
Given the Earnings-22 numbers, Parakeet TDT v2 looks like the strongest in-scope pick specifically for telephony/VoIP-quality audio (only ~4% relative WER degradation on 8kHz μ-law), separate from its AMI/TED-LIUM ranking. Granite Speech 4.0-1B-speech's combination of best clean accuracy and best absolute accented-speech accuracy, in a much smaller package than the 8B model, makes it the strongest all-around candidate in this entire report for an app that needs both general accuracy and reasonable robustness — pending the still-open question of its actual Apple Silicon runtime footprint (Q2 gap).

### Gaps
- **No reliable source found** for accented-English or noisy-audio robustness for: Moonshine (any variant), Apple SpeechAnalyzer (beyond the one Whisper-Small comparison above), Phi-4-multimodal beyond the Earnings-22 column, Nemotron-3.5-ASR-Streaming-0.6B (model card only says "trained on 10,000+ hours across diverse acoustic conditions," no benchmark breakdown).
- AfriSpeech-MultiBench's full numeric table (which would give exact per-model WER across multiple African accent groups) was not successfully extracted — this is the single best lead for a true multi-model accent comparison and should be re-fetched via the HTML version before final use.
- No evidence found of any model's robustness being tested on a standard accented-English corpus (e.g., Common Voice accent subsets, L2-ARCTIC, VoxPopuli accent evals) — only earnings-call audio (Earnings-22), African-accent-focused work, and informal blog claims.

---

## Notable scope additions / corrections found during research
- **IBM Granite Speech 4.0-1B-speech** is the single most important finding of this research: it has the best clean-average WER (5.52%) and the best AMI (far-field meeting) WER (8.44%) of every model in this report, in a package far smaller than Granite Speech 3.3-8B. It supersedes this report's initial (incomplete) read that NVIDIA Canary-Qwen-2.5B was the clear overall leader.
- **NVIDIA Nemotron-3.5-ASR-Streaming-0.6B** (released 2026-06-04) — NVIDIA's actual native-streaming ASR model (the Canary/Parakeet models in the original scope are not natively streaming). OpenMDW-1.1 license, 40 language-locales, no Apple Silicon port found yet, and not on the accuracy leaderboard.
- **Mistral Voxtral-Mini-4B-Realtime-2602** ("Voxtral Transcribe 2" family, released 2026-02-04) — Mistral's actual native-streaming ASR model, confirmed on the leaderboard at ~4B params, Apache 2.0. Its API-only companion, Mini Transcribe V2, is proprietary and not locally runnable. No Apple Silicon port found yet.
- **IBM Granite Speech 4.1-2B and 5.0 Turbo CTC-470M**, reported only in secondary blogs (not found on the live leaderboard or independently located on HF Hub in this research) — treat as unverified pending direct confirmation, despite being in scope per the task's "3.3 8B or newer" wording.
- **Moonshine Streaming** (tiny/small/medium) is confirmed as a real, independently-benchmarked, accurate release (not just a community rehost) via its direct appearance on the live Open ASR Leaderboard — and it is competitive with or better than much larger models on both TED-LIUM and AMI.
