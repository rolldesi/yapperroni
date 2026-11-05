# Independent, Cross-Vendor STT Accuracy Benchmarks (snapshot: October 8, 2026)

Scope note: this covers only benchmarks that score **multiple vendors/models on the same audio**. Single-vendor "we beat Whisper" blog posts are excluded or explicitly flagged as vendor-reported. Whisper large-v3 and large-v3-turbo are called out as anchor rows in every table where available.

---

## Artificial Analysis Speech-to-Text leaderboard (artificialanalysis.ai): what is AA-WER, which datasets make it up, and what are the current WER/price/speed values for every model listed?

### Takeaway
AA-WER is a duration-weighted composite WER across 3 curated datasets (AgentTalk 50%, VoxPopuli-Cleaned-AA 25%, Earnings22-Cleaned-AA 25%), run on identical audio across ~50+ commercial APIs and open models, with price-per-1,000-minutes and a "Speed Factor" (real-time multiple) reported alongside. The methodology changed versions during 2026 (v2.0 → v2.2), and the #1 ranked model changed multiple times (ElevenLabs Scribe v2 → MAI-Transcribe-2 → Fun-Realtime-ASR-preview) as new entrants were added — treat any single WER number as a snapshot, not a stable ranking.

### Cited Findings
- AA-WER methodology (v2.2, as published on the methodology page): "WER = (Substitutions + Insertions + Deletions) ÷ Words in Reference," computed per-dataset as an audio-duration-weighted average, then combined as a weighted average of 50% AA-AgentTalk + 25% VoxPopuli-Cleaned-AA + 25% Earnings22-Cleaned-AA — [Artificial Analysis Methodology](https://artificialanalysis.ai/speech-to-text/methodology)
- Dataset composition per the methodology page: AA-AgentTalk = proprietary, "speech relevant to voice agent use cases," 469 samples / ~250 minutes; VoxPopuli-Cleaned-AA = European parliamentary proceedings (English), 628 samples / ~119 minutes; Earnings22-Cleaned-AA = corporate earnings calls with technical language and overlapping speakers, 6 samples / ~115 minutes (total eval set ≈ 8 hours) — [Artificial Analysis Methodology](https://artificialanalysis.ai/speech-to-text/methodology)
- Transcripts are normalized before scoring using "OpenAI's Whisper normalizer plus custom additions covering ID formatting, spelling variants, technical punctuation, unit abbreviations" — [Artificial Analysis Methodology](https://artificialanalysis.ai/speech-to-text/methodology)
- Speed Factor = Audio Duration ÷ API Response Time (>1.0 means faster than real time); Price is normalized to "estimated cost per 1,000 minutes of audio transcribed" across duration-based, token-based, and subscription pricing models — [Artificial Analysis Methodology](https://artificialanalysis.ai/speech-to-text/methodology)
- Non-streaming leaderboard table, as scraped Oct 8, 2026 (AA-WER %, price USD/1,000 min, Speed Factor):

| Model | Provider | AA-WER | $/1,000 min | Speed Factor |
|---|---|---|---|---|
| Scribe v2 | ElevenLabs | 2.2% | 3.67 | 75.2 |
| Universal-3 Pro | AssemblyAI | 3.1% | 3.50 | 106.8 |
| Universal | AssemblyAI | 3.8% | 2.50 | 115.6 |
| Nova-3 | Deepgram | 5.2% | 4.30 | 628.1 |
| GPT-4o Transcribe | OpenAI | 4.0% | 6.00 | 36.1 |
| GPT-4o Mini Transcribe | OpenAI | 4.5% | 3.00 | 53.5 |
| Whisper Large v3 | OpenAI (hosted) | 4.1% | 6.00 | 27.8 |
| Whisper Large v3 | fal.ai (hosted) | 4.1% | 1.15 | 108.4 |
| Chirp 3 | Google | 4.3% | 16.00 | 31.3 |
| Gemini 3.5 Transcribe | Google | 2.6% | 5.00 | 88.6 |
| Amazon Transcribe | AWS | 4.1% | 6.00 | 28.1 |
| MAI-Transcribe-2 | Microsoft AI | 2.0% | 1.67 | 345.9 |
| Speechmatics Enhanced | Speechmatics | 4.0% | 12.50 | 77.9 |
| Rev AI | Rev AI | 5.9% | 3.33 | 12.8 |
| Solaria-3 | Gladia | 3.2% | 10.16 | 66.5 |
| Soniox v5 Async | Soniox | 3.8% | 1.66 | 36.7 |
| Voxtral Small | Mistral | 2.8% | 4.00 | 66.3 |
| Canary Qwen 2.5B | NVIDIA (hosted) | 4.3% | 0.74 | 8.7 |

  — [Artificial Analysis — Speech to Text, non-streaming](https://artificialanalysis.ai/speech-to-text/non-streaming)
- Per an Oct 2026 search-indexed snapshot of the same page, the overall #1 by accuracy was "Fun-Realtime-ASR-preview" at 1.7% AA-WER, followed by "ElevenLabs Scribe v2" at 2.2% and "MAI Transcribe 1.5" at 2.4%; this ranking was also seen dated to a June 2, 2026 crawl — [benchmarklist.com mirror of AA non-streaming](https://benchmarklist.com/benchmarks/artificial_analysis_speech_to_text_non_streaming/)
- An earlier AA-WER v2.0 snapshot (reported via a secondary tech blog, not independently re-verified by this researcher) had: ElevenLabs Scribe v2 2.3%, Google Gemini 3 Pro 2.9%, Mistral Voxtral Small 3.0%, Google Gemini 3 Flash 3.1%, ElevenLabs Scribe v1 3.2%, OpenAI Whisper Large v3 4.2% ("mid-pack"), Alibaba Qwen3 ASR Flash 5.9%, Amazon Nova 2 Omni 6.0%, Rev AI 6.1% — [the-decoder.com: ElevenLabs and Google dominate Artificial Analysis updated speech-to-text benchmark](https://the-decoder.com/elevenlabs-and-google-dominate-artificial-analysis-updated-speech-to-text-benchmark/)
- Artificial Analysis also runs a separate **AA-WER Streaming** leaderboard (latency + accuracy for real-time/streaming STT), where Meta's "Muse Voice Transcribe" was reported leading with 3.1% WER at roughly $0.18/hour of audio as of a Sept 2026 snapshot — [search-indexed AA streaming coverage, Oct 2026]
- Artificial Analysis frames itself as an independent third party benchmarking ASR, TTS, and speech-to-speech models, distinct from vendor-published numbers — [Inside Artificial Analysis: Independent AI Voice Benchmarks](https://www.besthub.dev/articles/inside-artificial-analysis-independent-ai-voice-benchmarks-for-asr-tts-and-speech-to-speech-86d35f2b095b)

### Inferences
- The AA leaderboard is volatile month-to-month in 2026 (new entrants like MAI-Transcribe-2, Fun-Realtime-ASR-preview, Gemini 3.5 Transcribe repeatedly retake #1), so a team mapping its own Whisper measurement onto AA-WER should anchor on the **Whisper large-v3 row specifically** (consistently ~4.0–4.2% AA-WER across the snapshots we found) rather than the shifting #1 position.
- Price/accuracy is not well correlated: the cheapest-per-minute options (Canary Qwen 2.5B at $0.74/1k min, Soniox at $1.66/1k min) are mid-pack on WER, while the most accurate (MAI-Transcribe-2, ElevenLabs Scribe v2) are mid-priced, and the most expensive (Google Chirp 3 at $16/1k min, Speechmatics Enhanced at $12.50/1k min) are not the most accurate.
- Two different OpenAI Whisper Large v3 rows exist on the same leaderboard (OpenAI-hosted at $6.00/1k min vs. fal.ai-hosted at $1.15/1k min) with **identical WER (4.1%) and very different Speed Factor (27.8 vs 108.4)** — confirms WER is a property of the model/decoding config, not the hosting provider, while speed and price vary by host.

### Gaps
- Could not independently confirm the exact AA-WER value for Whisper large-v3-**turbo** on the current AA leaderboard — it did not appear as a distinct row in the scraped table (OpenAI's AA rows list "Whisper Large v3" but not explicitly "turbo"); flag as a gap for the report writer to resolve via a direct re-check of artificialanalysis.ai/speech-to-text/non-streaming filtering for "turbo."
- Could not fully reconcile the three different snapshots (v2.0 blog-reported, June 2026 mirror, and the live Oct 8 2026 page) into one internally consistent table — the methodology version (v2.0 vs v2.2) changed the dataset mix, which plausibly explains some of the WER drift (e.g., Scribe v2 2.3% → 2.2%). Treat AA-WER as versioned, not a single constant.
- Did not independently verify AssemblyAI "Slam-1" as a distinct row; current AA table shows "Universal" and "Universal-3 Pro" as the AssemblyAI entries.
- Did not find an explicit Azure STT row on the AA table in the material retrieved (Azure appears in the HF/Picovoice-style benchmarks instead, see below).

---

## Hugging Face Open ASR Leaderboard: current average WER and per-dataset WER (AMI, Earnings22, GigaSpeech, LibriSpeech, SPGISpeech, TED-LIUM, VoxPopuli) and RTFx for top models, Whisper large-v3, and Whisper large-v3-turbo

### Takeaway
The Open ASR Leaderboard (hf-audio/open_asr_leaderboard on Hugging Face Spaces, backed by the arXiv paper 2510.06961) standardizes WER and inverse-real-time-factor (RTFx) across 86 open-source and proprietary systems on 12 datasets (7 used for the classic English short-form average: AMI, Earnings22, GigaSpeech, LibriSpeech clean/other, SPGISpeech, TED-LIUM, VoxPopuli). As of a May 6, 2026 mirrored snapshot, the top average-WER models were IBM Granite Speech 4.1 2B (5.33%), NVIDIA Canary-Qwen-2.5B (5.63%), and IBM Granite Speech 3.3 8B (5.74%); Whisper large-v3 sits well down the board at 7.4% average WER and Whisper large-v3-turbo at 7.8%.

### Cited Findings
- Paper description: "We standardize word error rate (WER) and inverse real-time factor (RTFx) evaluation for consistent accuracy-efficiency comparisons across model architectures and toolkits," evaluating "86 open-source and proprietary systems across 12 datasets, with English short- and long-form and multilingual short-form tracks." Finding: "Conformer-based encoders paired with transformer-based decoders achieve the best average WER, while connectionist temporal classification (CTC) and token-and-duration transducer (TDT) decoders offer superior RTFx." — [Open ASR Leaderboard paper, arXiv:2510.06961](https://arxiv.org/abs/2510.06961)
- Top-model average WER, per a May 6, 2026 third-party mirror of the live HF Space (NOT the primary HF page itself — the live Gradio table could not be scraped directly by this researcher; treat as a cached secondary source):

| Model | Avg. WER |
|---|---|
| IBM Granite Speech 4.1 2B | 5.33% |
| NVIDIA Canary-Qwen-2.5B | 5.63% |
| IBM Granite Speech 3.3 8B | 5.74% |
| NVIDIA Parakeet TDT v2 | 6.05% |
| Microsoft Phi-4 Multimodal | 6.02% |
| NVIDIA Parakeet TDT v3 | 6.32% |
| Kyutai STT 2.6B EN | 6.4% |
| Mistral Voxtral Small 24B | 6.62% |

  — [benchmarklist.com mirror of Open ASR Leaderboard](https://benchmarklist.com/benchmarks/open_asr_leaderboard/)
- Whisper large-v3 (per a secondary codesota.com model-card mirror, cross-referenced against known historical HF leaderboard values which independently corroborate ~7.4%): Average/"Open ASR Leaderboard" WER **7.4%**, RTFx **145.51**; per-dataset: LibriSpeech (test-clean) 1.8%, LibriSpeech (test-other) 3.6%, LibriSpeech overall 3.9%, SPGISpeech 2.9%, TED-LIUM 3.9%, VoxPopuli 9.5% — [codesota.com — Whisper Large v3](https://www.codesota.com/model/whisper-large-v3)
- Whisper large-v3-turbo (same mirror): Average "Open ASR Leaderboard" WER **7.8%**, RTFx **200.19**; per-dataset: LibriSpeech 4.2%, SPGISpeech 3.0%, TED-LIUM 3.6%, VoxPopuli 11.9%, GigaSpeech 10.1%, AMI-IHM 16.1%, Earnings-22 11.6%. Released Sep 2024, described as "pruned decoder, 8x faster than large-v3" — [codesota.com — Whisper Large v3 Turbo](https://www.codesota.com/model/whisper-large-v3-turbo)
- AMI (far-field meeting) and TED-LIUM (clean lecture) are the two extremes for both Whisper variants: large-v3-turbo scores 16.1% WER on AMI-IHM vs. only 3.6% on TED-LIUM — a >4x gap — confirming that far-field/overlapping-speaker audio is dramatically harder than clean lecture-style audio for Whisper-family models — [codesota.com — Whisper Large v3 Turbo](https://www.codesota.com/model/whisper-large-v3-turbo)

### Inferences
- Whisper large-v3 and large-v3-turbo both rank well outside the top of the Open ASR Leaderboard's open-model field (~7.4–7.8% avg WER vs. ~5.3–6.6% for the current top 8), meaning a team benchmarking its own Whisper numbers against this leaderboard should expect Whisper to look worse here than on AA-WER (where Whisper large-v3 is ~4.1%), because HF's dataset mix (AMI, Earnings22, GigaSpeech, SPGISpeech, TED-LIUM, VoxPopuli, LibriSpeech) is weighted far more heavily toward hard/far-field/noisy conditions than Artificial Analysis's 3-dataset mix.
- large-v3-turbo is not uniformly better than large-v3 on this leaderboard: turbo's LibriSpeech WER (4.2%) is *worse* than large-v3's (3.9%), even though turbo is ~8x faster — accuracy/speed tradeoff, not a strict upgrade, consistent with OpenAI's own "pruned decoder" description.

### Gaps
- Could not retrieve a single authoritative, dated row-by-row table directly from the live `huggingface.co/spaces/hf-audio/open_asr_leaderboard` page (it renders via Gradio/JS and returned only metadata to the fetch tool); all WER numbers above come from third-party mirrors (benchmarklist.com, codesota.com) that could not be timestamped precisely beyond "May 6, 2026" for the top-8 table. The report writer should flag these as secondary/cached, not primary-source-verified, and ideally have someone re-pull the live Space table for a final sanity check.
- Could not get NVIDIA Canary-Qwen-2.5B's or Parakeet's per-dataset AMI/TED-LIUM breakdown (only Whisper's per-dataset breakdown was retrievable from the mirror site).
- Could not confirm whether any commercial API rows (e.g., a cloud ASR vendor) appear directly on the HF Open ASR Leaderboard — all evidence found concerns open-weight/open-source models only; this leaderboard appears to be open-model-only, unlike Artificial Analysis which mixes both.
- The June 2026 Treble Technologies + Hugging Face "Far Field ASR (FFASR) Leaderboard" was mentioned as a new benchmark "designed to evaluate ASR models under realistic far-field acoustic conditions" but no WER numbers from it were retrieved — noting as a lead for further research, not a confirmed data point. — [Treble Technologies press release reference, via rits.shanghai.nyu.edu summary](https://rits.shanghai.nyu.edu/ai/cohere-transcribe-2b-open-source-asr-model-takes-1-on-leaderboard/)
- A March 26, 2026 release claims "Cohere Transcribe," a 2B-parameter open-source ASR model, took the #1 spot on the Open ASR Leaderboard at launch — this predates the May 6, 2026 snapshot above (which shows IBM/NVIDIA at top, not Cohere), implying Cohere Transcribe was later overtaken; WER number for Cohere Transcribe itself was not found — gap. — [rits.shanghai.nyu.edu summary of Cohere Transcribe launch](https://rits.shanghai.nyu.edu/ai/cohere-transcribe-2b-open-source-asr-model-takes-1-on-leaderboard/)

---

## Other independent, multi-vendor STT benchmarks published 2025–2026 (academic papers, Voice Writer, Picovoice, independent blogs)

### Takeaway
The strongest genuinely independent, methodologically transparent cross-vendor benchmark found is an April 2025 Linguistic Data Consortium / University of Pennsylvania arXiv paper ("Evaluating Speech-to-Text Systems with PennSound") that ran ~10 hours of real poetry-reading/discussion audio through AWS, Azure, Google, IBM, NVIDIA NeMo, Rev.ai, Whisper, and whisper.cpp, scored with NIST's SCTK toolkit. Rev.ai and Whisper were the top two performers (9.0% and 9.5% WER respectively), and the paper separately documents a serious Whisper large-v3 hallucination problem (large-v3 had a Final-Insertion-Count of 124 hallucinated trailing tokens vs. only 76 for large-v2, and large-v3-turbo spiked to 1,601 trailing hallucinated tokens under default decoding settings). Picovoice's own open-source speech-to-text-benchmark framework and Voice Writer's methodology notes were also identified but detailed current-run numbers could not be retrieved in this pass. A Lingvanex-published multi-API comparison was found but is vendor marketing, not independent, and is flagged as such.

### Cited Findings
- **PennSound study (independent, peer-reviewable, LDC/UPenn, published April 8, 2025):** "A random sample of nearly 10 hours of speech from PennSound... was used as a benchmark to evaluate several commercial and open-source speech-to-text systems... Based on word error rate, Rev.ai was the top performer, and Whisper was the top open source performer (as long as hallucinations were avoided)." Systems tested: Amazon Transcribe, Microsoft Azure AI Speech, Google Cloud Speech-to-Text, IBM Watson Speech to Text, Rev.ai, NVIDIA NeMo, OpenAI Whisper, and whisper.cpp — [Wright, Liberman, Ryant, Fiumara — "Evaluating Speech-to-Text Systems with PennSound," arXiv:2504.05702](https://arxiv.org/abs/2504.05702)
- Full-sample WER table (Table 1, scored with NIST SCTK): AWS 9.8%, Azure 10.2%, Google 11.0%, IBM 14.4%, NeMo 10.9%, **Rev.ai 9.0%** (best overall), **Whisper 9.5%** (best open-source), whisper.cpp 10.9% — [arXiv:2504.05702, Table 1](https://arxiv.org/abs/2504.05702)
- Whisper model-size/version ablation (Table 3: WER / Insertion-Error-Rate / Final-Insertion-Count, i.e., hallucinated trailing tokens) run under default decoding options: tiny 17.7/2.6/89, base 14.3/1.7/129, small 11.5/1.1/27, medium 11.1/1.1/55, **large 14.8/5.2/263**, **large-v2 10.5/1.0/76**, **large-v3 15.4/5.6/124**, **large-v3-turbo 11.2/2.9/1601** — [arXiv:2504.05702, Table 3](https://arxiv.org/abs/2504.05702)
- Critical methodology note from the paper: the main-trial Whisper row (WER 9.5%, used in Table 1) was large-v3-turbo run *with* `--word_timestamps True` and `--hallucination_silence_threshold` set to 0.1 or 0.5, which suppressed the hallucination problem seen in the Table 3 ablation (which used default options and showed turbo's WER jump to 11.2% with 1,601 extraneous hallucinated tokens). The paper explicitly warns: "Users of Whisper should be cautioned to be aware of runtime options, and whether the speed vs accuracy trade off is acceptable." — [arXiv:2504.05702, Section 3.1/4]
- Diarization error rate (DER, 3 systems that expose speaker labels): AWS 14.52, Azure 15.40, Rev.ai 15.49 — roughly tied — [arXiv:2504.05702, Table 2]
- Picovoice maintains an open-source `speech-to-text-benchmark` framework (Apache 2.0, code + data on GitHub) comparing Amazon Transcribe, Azure Speech-to-Text, Google Speech-to-Text (standard/enhanced), IBM Watson, OpenAI Whisper, and Picovoice's own Cheetah/Leopard engines, using LibriSpeech (test-clean/test-other), Common Voice, TED-LIUM, Multilingual LibriSpeech, and VoxPopuli, across English, French, German, Italian, Spanish, and Portuguese, reporting WER and a "Core-Hour" compute-efficiency metric — [Picovoice STT Benchmark docs](https://picovoice.ai/docs/benchmark/stt)
- Voice Writer (voicewriter.io) publishes a benchmark distinguishing **formatted WER** (counts punctuation/capitalization/number-format errors, relevant to note-taking UX) from **unformatted WER** (classic WER), arguing raw WER alone hides real differences like "two" vs "2" or "color" vs "colour" — [referenced via search aggregation of voicewriter.io methodology; could not fetch the live page's current numeric table directly in this pass]
- A Lingvanex-published comparison (dated April 30, 2025) tested Lingvanex, Deepgram Nova-2, AssemblyAI, Gladia, and Speechmatics across 12 languages using clean studio, phone-call, meeting, and street/café recordings, reporting WER/CER — but the article is explicitly authored by "Lingvanex specialists," presents Lingvanex favorably throughout, and lacks a transparent unified results table. **This is vendor marketing content, not an independent benchmark**, despite testing multiple competitors — [Lingvanex blog — Speech Recognition Accuracy Benchmark 2025](https://lingvanex.com/blog/speech-recognition-quality-comparison/)
- A separately search-indexed "Voice Arena STT Leaderboard" was referenced, reportedly showing "Reson8's resonant-1" leading a US-English board at 4.34% WER ahead of models from Microsoft AI, Google DeepMind, OpenAI, and Meta — found only in secondary search-result summary form; original source/methodology not retrieved — flagged as an unverified lead, not a confirmed finding.

### Inferences
- The PennSound paper is the single highest-confidence, truly independent (academic, non-vendor, transparent methodology, open data/code on GitHub) cross-vendor STT benchmark found in this research pass for 2025–2026, and it is the only source here that explicitly quantifies Whisper's hallucination behavior differences between large-v2, large-v3, and large-v3-turbo on identical audio — directly actionable for a team trying to map its own Whisper measurements onto a baseline, provided they check whether their Whisper run uses the same anti-hallucination decoding flags.
- Multiple "benchmark" sites discovered during this research (novascribe.ai, vexascribe.com, devtoollab.com — all citing suspiciously precise aggregate numbers like "Speechmatics Melia-1 aggregate WER 6.4% across 16 datasets / 904 audio files, dated July 2026") read as programmatic SEO/content-farm sites rather than primary research: no methodology paper, no raw data, inconsistent branding patterns typical of AI-generated comparison content. These numbers were **not included as findings** above and should not be relayed as citable facts without independent verification of the underlying site.

### Gaps
- Could not retrieve Voice Writer's actual current numeric leaderboard/table (only its stated methodology philosophy was found via search synthesis) — a direct fetch of voicewriter.io's benchmark page is recommended for the report writer if exact numbers are needed.
- Could not retrieve current numeric results from Picovoice's GitHub-hosted benchmark run (framework and dataset list confirmed, but no 2025/2026-dated WER table was surfaced in this pass).
- Could not verify the "Voice Arena STT Leaderboard" (Reson8 resonant-1, 4.34% WER) claim against a primary source — treat as unconfirmed.
- Did not find additional 2025–2026 academic (arXiv) papers beyond PennSound that benchmark commercial ASR APIs head-to-head on shared audio; this is a plausible gap in the research rather than confirmed absence — further search with different terms (e.g., specific vendor-pair comparisons, specific domains like medical/legal transcription) may surface more.

---

## How do the leaderboards rank providers relative to Whisper large-v3/turbo (ratio or absolute difference)?

### Takeaway
Relative standing is strongly dataset-dependent: on Artificial Analysis's agent/earnings-call-weighted mix, Whisper large-v3 is mid-pack (~4.1–4.2% AA-WER, roughly 2x the error rate of the top commercial systems like ElevenLabs Scribe v2 or MAI-Transcribe-2 at ~2.0–2.2%). On the Hugging Face Open ASR Leaderboard's harder, far-field/noisy-heavy 7-dataset mix, Whisper large-v3/turbo fall further back in absolute terms (~7.4–7.8% avg WER vs. ~5.3–6.6% for the current top open models, roughly 1.1–1.5x the error rate of the leaders). On the independent PennSound academic benchmark (real-world poetry/discussion audio), Whisper (9.5% WER, with anti-hallucination flags set) was essentially tied with the best commercial system tested (Rev.ai, 9.0%) and beat four other commercial APIs (Azure, Google, IBM, NVIDIA NeMo).

### Cited Findings
- AA-WER (Oct 2026 snapshot): Whisper large-v3 4.1% vs. best-in-class ElevenLabs Scribe v2 2.2% → Whisper's error rate is ~1.86x the leader's; vs. MAI-Transcribe-2 2.0% → ~2.05x — [Artificial Analysis non-streaming leaderboard](https://artificialanalysis.ai/speech-to-text/non-streaming)
- HF Open ASR Leaderboard (May 2026 mirror): Whisper large-v3 7.4% / large-v3-turbo 7.8% vs. leader IBM Granite Speech 4.1 2B at 5.33% → large-v3 is ~1.39x and large-v3-turbo ~1.46x the leader's error rate — [codesota.com Whisper mirrors](https://www.codesota.com/model/whisper-large-v3) and [benchmarklist.com Open ASR mirror](https://benchmarklist.com/benchmarks/open_asr_leaderboard/)
- PennSound (absolute WER, real-world non-lab audio): Whisper 9.5% vs. Rev.ai 9.0% (best) → Whisper's error rate is ~1.06x Rev.ai's, i.e. nearly tied, and better than AWS (9.8%), Azure (10.2%), NeMo (10.9%), whisper.cpp (10.9%), Google (11.0%), and IBM (14.4%) — [arXiv:2504.05702, Table 1]

### Inferences
- A team should not use a single cross-leaderboard "Whisper is X% worse than the market" multiplier — the ratio of Whisper's WER to the best commercial system ranges from roughly 1.0x (real-world PennSound audio) to ~1.4x (HF's hard/far-field mix) to ~1.9–2x (AA's agent-call-weighted mix), so the honest mapping is: **Whisper is competitive-to-best on natural, relatively clean long-form speech, and meaningfully behind specialized commercial models on noisy/overlapping/far-field or voice-agent-style short utterances.**
- Because large-v3-turbo's accuracy is not a strict improvement over large-v3 (worse on LibriSpeech per HF leaderboard; prone to much larger hallucinated-tail-token counts under default settings per PennSound), a team's own turbo measurement should be sanity-checked against whichever anti-hallucination decoding flags each leaderboard actually used — different flags will shift turbo's apparent WER by several points.

### Gaps
- No single leaderboard among those found publishes a direct "Whisper large-v3 vs. large-v3-turbo vs. every commercial vendor" ratio table — every ratio above was computed by this researcher from the raw WER numbers reported by each source, not quoted directly from a publisher's own ranking commentary. The report writer should present these as derived comparisons, not as leaderboard-stated rankings.
