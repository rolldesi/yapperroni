# Consumer/Prosumer Dictation and Meeting-Transcription Products (as of October 2026)

Research scope: Wispr Flow, Superwhisper, MacWhisper, Aqua Voice, Willow Voice, VoiceInk, Spokenly, Apple Dictation/SpeechAnalyzer, Granola, Otter.ai, Fireflies, Fathom, tl;dv, Cluely — engine, pricing, live-transcription, platform, and accuracy evidence. All facts dated; vendor claims explicitly marked vs. independent tests.

## Wispr Flow

### Takeaway
Wispr Flow is a cloud-only dictation app that historically wrapped OpenAI Whisper but, as of August 2026, ships a proprietary 2B-parameter model ("Canto") it claims cuts WER in noisy/accented conditions from >30% to ~5–10%; pricing is subscription-based ($15/mo or $12/mo annual Pro), and the company has had real privacy controversies (default-off Zero Data Retention, a LinkedIn word-mining incident, and a disputed SOC 2 audit).

### Cited Findings
- Historically, Wispr Flow was built on "OpenAI's open-source Whisper model," reported at approximately 65% accuracy on technical terms (vendor-comparison claim) — [getvoibe.com](https://www.getvoibe.com/resources/openai-whisper-vs-wispr-flow/)
- August 17, 2026: Wispr raised a $280M Series B at a $2B valuation (Menlo Ventures-led, $361M total funding) and launched "Canto," its first proprietary speech model — a 2-billion-parameter model trained for noisy rooms, accents, and wind — claimed to cut WER from >30% to ~5–10% in difficult conditions (vendor claim) — [vktr.com](https://www.vktr.com/ai-platforms/wispr-hits-2b-valuation-launches-canto-voice-model/)
- Pricing (2026): Basic free (2,000 words/week desktop, 1,000/week iPhone, unlimited Android); Pro $15/mo monthly or $12/mo ($144/yr) annual; Teams $12/user/mo monthly or $10/user/mo annual (3-seat minimum); Enterprise custom. 14-day Pro trial, no card required. Students: 3 months free then 50% off (~$6/mo annual) — [pricingsaas.com](https://pricingsaas.com/companies/wisprflow), [getvoibe.com](https://www.getvoibe.com/resources/wispr-flow-pricing/)
- Wispr Flow is cloud-only — audio always leaves the Mac for transcription; audio is sent to third-party cloud servers including OpenAI and Meta — [en.wikipedia.org/Wispr_Flow summary via search]
- Privacy Mode (adds Zero Data Retention) is **off by default**; when off, dictation data may be used to improve the product. The app can read device keystrokes, which drew security concern — [getvoibe.com](https://www.getvoibe.com/resources/wispr-flow-linkedin-dictation-analysis/)
- A Wispr Flow team member published word-frequency data mined from user dictations (filler words by country), which was possible because Privacy Mode defaults off — [getvoibe.com](https://www.getvoibe.com/resources/wispr-flow-linkedin-dictation-analysis/)
- March 2026: an anonymous newsletter alleged the compliance firm "Delve" issued questionable SOC 2 audits for several startups including Wispr Flow; Wispr re-engaged a traditional auditor and republished documentation — [search summary, original newsletter not directly fetched]
- Independent benchmark (Superwhisper's own public benchmark suite, updated Sept 3, 2026): "Wispr Flow (raw)" scored blended score 75, overall WER 8.7% (range 3.5–16.2% across 8 datasets: AMI Meetings, Common Voice Australian/spontaneous English, Earnings-22 with/without vocabulary, LibriSpeech Other, Loquacious, phonetic vocabulary), response time 1.28s. Note: this is the *raw* model result "for comparison, not shipped in the app" per the page, and is published by a direct competitor (Superwhisper) — [superwhisper.com/benchmarks/wispr-flow-raw](https://superwhisper.com/benchmarks/wispr-flow-raw)
- A separate vendor-authored comparison (LumeVoice, a competing dictation app) claims its own app beats Wispr Flow: LumeVoice WER 1.2% (standard English) vs Wispr Flow 2.1%; both numbers are self-published marketing by a competitor and should be treated as unverified — [lumevoice.com](https://lumevoice.com/es/blog/app-dictado-mac-mas-precisa-2026/)

### Inferences
- Wispr Flow's move from wrapping Whisper to a proprietary Canto model suggests the company judged off-the-shelf cloud ASR (Whisper/Deepgram-class) insufficient for noisy/accented real-world dictation and was willing to fund a custom model — relevant precedent for Yapperroni's local-vs-cloud build decision.
- The gap between vendor-claimed WER (~5–10% per Wispr) and the independent-ish Superwhisper benchmark (8.7% blended) is roughly consistent, suggesting Wispr's claims are not wildly inflated, though "difficult conditions" baseline (>30%) is unverified against a named prior model.

### Gaps
- No independent, non-competitor benchmark of the production Canto model (post-August 2026) was found — all accuracy numbers trace to Wispr itself or to a direct competitor (Superwhisper).
- Original Delve/SOC2 controversy newsletter was not directly retrieved; details are second-hand via aggregator summary.

## Superwhisper

### Takeaway
Superwhisper is a local-first macOS/Windows/iOS dictation app offering free local Whisper/Parakeet models and a paid tier unlocking larger local models plus optional cloud processing and BYOK; pricing is $8.49/mo, $84.99/yr, or $249.99 lifetime (breakeven vs. annual at ~3 years).

### Cited Findings
- Pricing (2026): Free tier (small local Whisper models, up to 3 custom modes); Pro $8.49/mo or $84.99/yr; Lifetime $249.99 one-time (all paid features + future updates on macOS/Windows/iOS) — [getvoibe.com](https://www.getvoibe.com/resources/superwhisper-pricing/)
- Local model lineup: Whisper Tiny through Large-V3-Turbo, plus NVIDIA Parakeet V2 and V3; small models free/unlimited, larger Whisper/Parakeet models and cloud processing behind Pro; Pro also unlocks OpenAI Whisper Large (cloud), BYOK — [getvoibe.com](https://www.getvoibe.com/resources/superwhisper-pricing/)
- Superwhisper publishes its own cross-vendor benchmark suite (8 datasets: AMI Meetings, Common Voice AU/spontaneous English, Earnings-22 ±vocabulary, LibriSpeech Other, Loquacious, phonetic vocabulary) comparing 16 systems including Wispr Flow, Deepgram Nova-3, ElevenLabs Scribe v2, Gemini 3.5 Transcribe, GPT Transcribe, NVIDIA Parakeet V2/V3, and five Whisper variants (Large-V2, Large-V3, Large-V3-Turbo, Medium, Small, Tiny) — [superwhisper.com/benchmarks/wispr-flow-raw](https://superwhisper.com/benchmarks/wispr-flow-raw)
- Caveat: this benchmark is self-published by Superwhisper, a direct competitor to the apps it benchmarks (including its own "S1 Voice" and "Ultra" variants) — treat relative rankings with appropriate skepticism despite the methodology appearing dataset-based and reproducible.

### Inferences
- Superwhisper's willingness to publish an open, multi-dataset benchmark (even if self-interested) is one of the few quasi-structured comparative data sources available in this space; Yapperroni could replicate its dataset list (AMI, Common Voice, Earnings-22, LibriSpeech, Loquacious) for its own neutral internal benchmark.

### Gaps
- No fully independent (non-vendor) benchmark of Superwhisper itself was found.

## MacWhisper

### Takeaway
MacWhisper is a one-time-purchase, fully local macOS transcription app built on Whisper (via local inference), with Pro ($69–€59) unlocking Large-v3/v4 models, batch transcription, diarization, and real-time mic/system-audio transcription; no subscription.

### Cited Findings
- Pricing: Free tier with small models; Pro $69 one-time (Gumroad lists €59 ≈ $69 USD); Pro Max $149 one-time. No subscription required for any tier — [getvoibe.com](https://www.getvoibe.com/resources/macwhisper-pricing/)
- Pro unlocks larger Whisper models (Large-v3 and "v4"), batch transcription, speaker diarization, and real-time transcription from microphone or system audio — [getvoibe.com](https://www.getvoibe.com/resources/macwhisper-pricing/)
- Marketing framing: "dramatically cheaper than cloud services like Otter.ai or Rev.com ... and fundamentally more private since audio never leaves your device" (vendor/reviewer claim) — [getvoibe.com](https://www.getvoibe.com/resources/macwhisper-pricing/)

### Inferences
- MacWhisper is the clearest "local Whisper, one-time price" comparator for Yapperroni — effective cost per hour of audio is near-zero after the one-time purchase (only electricity/compute), versus per-minute cloud API billing.

### Gaps
- No independent WER numbers specific to MacWhisper's implementation (vs. raw whisper.cpp) were found.

## Aqua Voice

### Takeaway
Aqua Voice runs a proprietary ASR model ("Avalon") under its "Aqua Engine," which it claims ranked #1 among proprietary models on the independent OpenASR leaderboard in October 2025; pricing is $8/mo (web, annual) or $12.99/mo (iOS), targeted at technical/coding dictation.

### Cited Findings
- Pricing: Starter free (1,000 words one-time, not recurring — roughly 8 minutes of speech); Pro $8/mo billed annually (web) or $12.99/mo via iOS App Store — includes unlimited words, Aqua Engine, Avalon model, 800 custom-dictionary values; Team $12/mo (annual) adds centralized billing; Enterprise custom (SSO/SAML, Zero Data Retention, advanced reporting, volume discounts) — [capterra.com](https://www.capterra.com/p/10044478/Aqua-Voice/), [spokenly.app](https://spokenly.app/blog/aqua-voice-pricing)
- "Aqua runs its own proprietary model, Avalon, which debuted at #1 among proprietary models on the independent OpenASR leaderboard in October 2025" (comparison-site claim, original leaderboard not independently fetched) — [lumevoice/getvoibe-style aggregator, via search summary]

### Inferences
- Aqua Voice is the second dictation vendor (after Wispr) to have built a fully proprietary model rather than wrapping Whisper/Deepgram, suggesting that at the top of this market, differentiated accuracy increasingly requires custom acoustic models rather than prompt/formatting layers on commodity ASR.

### Gaps
- The OpenASR leaderboard placement claim was not verified against the primary Hugging Face OpenASR leaderboard directly; treat as an unconfirmed secondary claim.
- No disclosed architecture details for Avalon (parameter count, training data) were found.

## Willow Voice

### Takeaway
Willow Voice does not publicly disclose its core speech-recognition engine; it runs cloud-only (not stored, per vendor) and uses a Llama-based text-to-text formatting layer on top of the (undisclosed) ASR output. Pricing matches Wispr Flow almost exactly: Free (2,000 words/week), Individual $12/mo annual ($15/mo monthly, $144/yr), Team $10/mo annual (3-seat min), Enterprise custom with SOC 2/HIPAA/zero-data-retention.

### Cited Findings
- "Willow does not publicly disclose what speech recognition powers its product" — unlike Aqua (proprietary Avalon model), Willow's differentiation is described as happening in a text-to-text formatting pipeline "tuned on Meta's Llama models" for punctuation/tone/app-specific formatting, plus context-awareness of the active app — [search aggregator summary citing willowvoice.com/notion overview]
- "Willow runs in the cloud for speed and accuracy, but the company never stores or collects your voice or data" (vendor claim, not independently audited) — [same aggregator]
- Pricing: Free (2,000 words/week); Individual $12/mo billed annually ($15/mo monthly, $144/yr); Team $10/mo billed annually (3-seat minimum); Enterprise custom with SOC 2, HIPAA, zero data retention — [getvoibe.com](https://www.getvoibe.com/resources/willow-voice-pricing/), [willowvoice.com/pricing](https://willowvoice.com/pricing)

### Inferences
- Willow's pricing is nearly identical to Wispr Flow's (same $12/$15 structure), suggesting the two compete directly on price while differentiating on claimed privacy posture and (for Wispr) now a proprietary model.

### Gaps
- No disclosure found of which cloud ASR vendor underlies Willow (Whisper, Deepgram, AssemblyAI, or proprietary) — a clear gap, since the formatting-layer-on-top-of-undisclosed-ASR pattern is common in this market and makes vendor dependency hard to assess.
- No independent accuracy benchmark found for Willow Voice specifically.

## VoiceInk

### Takeaway
VoiceInk is an open-source (GPLv3), $39.99 one-time-license macOS dictation app that defaults to fully local whisper.cpp inference but also supports a wide range of optional cloud STT providers (bring-your-own-key): Groq, OpenAI, Deepgram, ElevenLabs, Speechmatics, Soniox, Anthropic, Gemini, Mistral, Cerebras, OpenRouter, plus local Ollama.

### Cited Findings
- VoiceInk "leverages local AI models, specifically ... whisper.cpp for high-performance inference of OpenAI's Whisper model," ensuring 100% offline processing by default — [search aggregator]
- Open source under GPLv3, 3,700+ GitHub stars; paid license $39.99 one-time; installable via `brew install --cask voiceink`; requires macOS 14.0+ — [sourcepulse.org](https://www.sourcepulse.org/projects/2336261), [converter.brightcoding.dev](https://converter.brightcoding.dev/blog/stop-paying-for-voice-transcription-voiceink-is-the-free-macos-fix)
- Optional cloud API providers (BYOK, only activated when a key is supplied): Groq, OpenAI, Deepgram, ElevenLabs, Speechmatics, Soniox, Anthropic, Gemini, Mistral, Cerebras, OpenRouter, and local Ollama; supports custom OpenAI-compatible endpoints — [tryvoiceink.com/privacy](https://tryvoiceink.com/privacy)
- Feature set: "Power Mode" for per-app/per-URL configuration profiles, personal dictionary for custom terminology — [search aggregator]

### Inferences
- VoiceInk is the most direct architectural comparator for Yapperroni's likely design: local whisper.cpp by default, optional BYOK cloud fallback for users who want higher accuracy/multilingual coverage. Its $39.99 one-time price point plus free/open-source option shows the local-first segment can sustain a business without per-minute billing.

### Gaps
- No independent WER benchmark of VoiceInk's whisper.cpp implementation vs. other local apps (MacWhisper, Superwhisper) was found.

## Spokenly

### Takeaway
Spokenly is positioned as a free-local-model/BYOK-first dictation app ("free forever" with local models or your own API keys) with an optional Pro cloud tier at $8.33–$9.99/mo; claims "Whisper-class accuracy" across 100+ languages with on-device and cloud modes.

### Cited Findings
- Pricing: three tiers — Local models (free forever, unlimited), Your own API keys (free forever, zero payment to Spokenly), Pro ($8.33/mo billed annually at $99.99/yr, or $9.99/mo flat) — [capterra.com](https://www.capterra.com/p/10046295/Spokenly/)
- Marketing claim: "100+ languages with Whisper class accuracy," on-device and cloud modes, works via one keyboard shortcut in any app, available on Mac, Windows, iPhone, iPad — [capterra aggregator summary]

### Inferences
- Spokenly's free-local/BYOK model is the most aggressive pricing structure found among dictation apps (effectively $0 for unlimited local use), directly undercutting subscription players like Wispr/Willow on cost, in exchange for requiring users to supply their own API key for cloud-grade accuracy.

### Gaps
- No independent accuracy data or specific underlying local-model choice (Whisper size/version, or Parakeet) was confirmed beyond the general "Whisper class" marketing claim.

## Apple Dictation (legacy) vs. Apple SpeechAnalyzer/SpeechTranscriber (macOS 26)

### Takeaway
These are two different generations of Apple's speech stack and should not be conflated: legacy on-device "Apple Dictation" (SFSpeechRecognizer-era) scores poorly (reviewer-estimated 75–85% accuracy / 15–18% WER), while the new SpeechAnalyzer/SpeechTranscriber framework introduced for macOS 26 is independently benchmarked to *beat* Whisper Small on both accuracy and speed on clean/noisy LibriSpeech audio, fully on-device.

### Cited Findings
- Legacy comparison (reviewer blog, not dated to a specific benchmark run, 2026 content): "Apple Dictation has an accuracy of 75–85%, while OpenAI's Whisper model achieves 95 to 97 percent"; "Apple Dictation shows a real-world WER of 15–18%, while Whisper Large V3 achieves 8–12% WER"; Apple Dictation "falls apart for professional, all-day use with spotty accuracy on technical language" — [getvoibe.com](https://www.getvoibe.com/resources/apple-dictation-vs-openai-whisper/) (vendor-aggregator claim, methodology not disclosed — treat as directional, not precise)
- **Independent benchmark #1** (MacGeneration/MacG, July 14, 2026, reporting on a benchmark run by "Inscribe" developers): SpeechAnalyzer WER 2.12% (clean) / 4.56% (noisy) vs. Whisper Small 3.74% (clean) / 7.95% (noisy); legacy SFSpeechRecognizer 9.02% (clean) / 16.25% (noisy). Methodology: 5,559 excerpts from LibriSpeech, English only, Mac M2 Pro/32GB, macOS 26.5.1, fully local processing. SpeechAnalyzer "approximately three times faster," processing an hour of audio in minutes with punctuation/capitalization. Limitation noted: only read English speech tested, not conversational/meeting audio or varied accents — [macg.co](https://www.macg.co/macos/2026/07/speechanalyzer-un-benchmark-confirme-que-la-transcription-dapple-bat-le-whisper-dopenai-309741)
- **Independent benchmark #2** (dev.to, published by the maker of "IraVoice," a commercial Mac dictation app that ships Apple's recognition path — discloses this conflict of interest): on LibriSpeech test-clean, 40 speakers (20F/20M), 4–10s clips: Apple SpeechAnalyzer 1.98% WER / 1.02% CER vs. whisper.cpp 1.8.4 ggml-small.en 4.28% WER / 1.79% CER (12 vs. 26 word edits across 607 reference words). Post-speech latency: Apple 125–132ms median (194–201ms p95) vs. whisper.cpp 122–125ms median (152–161ms p95) — i.e., comparable streaming latency in this specific test, even though the macG-reported Inscribe benchmark separately found ~3x throughput advantage for batch processing. Hardware: Apple M5 Max, 128GB RAM, macOS 26.5. Raw data published under CC BY 4.0 — [dev.to/iravoice](https://dev.to/iravoice/apple-speechanalyzer-vs-whispercpp-a-40-speaker-mac-benchmark-40i4)
- Earlier coverage (Gigazine, originally reported ~June 2025 and re-covered July 2026): "Apple's new transcription API 'SpeechAnalyzer' beats OpenAI's Whisper in speed tests," consistent directionally with both benchmarks above — [gigazine.net](https://www.gigazine.net/gsc_news/en/20250619-apple-speech-analyzer), [gigazine.net](https://www.gigazine.net/gsc_news/en/20260714-apple-speech-analyzer-benchmark/)
- Apple's SpeechTranscriber covers only ~30 languages/locales and requires macOS 26+/recent Apple Silicon, vs. Whisper's 99+ languages across any platform — [search aggregator synthesis of multiple sources]

### Inferences
- Across two separately-sourced benchmarks (MacG/Inscribe and the IraVoice developer), both run on LibriSpeech with Apple's own hardware, Apple SpeechAnalyzer consistently beats Whisper Small (not large-v3 or large-v3-turbo) by roughly 2x on WER for clean audio and shows a comparable-or-better margin on noisy audio, while running several times faster for batch jobs. **Neither test compared directly against Whisper large-v3-turbo** — both used Whisper Small as the "whisper.cpp" comparator, which is a materially weaker model than large-v3-turbo. This is a significant gap for Yapperroni's specific question.
- Both available benchmarks are run on read-speech (LibriSpeech), English-only, which likely favors Apple's modern on-device model but does not validate behavior on accented, multi-speaker, or meeting/VC-call-style audio — exactly the conditions Yapperroni cares about.
- Given Apple's free, on-device, ~3x-faster-than-Whisper-Small result, a macOS-only dictation product has a strong case for defaulting to SpeechAnalyzer/SpeechTranscriber for English on macOS 26+, with Whisper (local or cloud) as a fallback for pre-26 systems, non-English languages, or accuracy-critical noisy/accented scenarios pending a large-v3-turbo-specific comparison.

### Gaps
- **No benchmark found that directly compares Apple SpeechAnalyzer against Whisper large-v3-turbo** (the specific model Yapperroni asked about) — both independent tests used Whisper Small. This should be flagged to the report writer as an open question; Yapperroni may need to run its own benchmark (e.g., reusing the LibriSpeech test-clean + Common Voice accent sets referenced by Superwhisper's public benchmark) to get a large-v3-turbo data point.
- No benchmark found testing Apple's engine on noisy multi-speaker meeting/VC-call audio or non-US accents specifically (only "noisy" as a LibriSpeech-perturbed condition, not real-world crosstalk).

## Granola

### Takeaway
Granola is a cloud-based meeting notetaker (live transcription supported) that does not publicly disclose its transcription-provider vendor; pricing is Free (Basic, limited note-history window), Business $14/user/month, Enterprise $35/user/month.

### Cited Findings
- Granola's own docs: "Granola passes audio directly from your microphone and system audio to our transcription provider" — vendor name not disclosed; "Granola does not record or save audio or video at any point during the call" — [docs.granola.ai/help-center/taking-notes/transcription](https://docs.granola.ai/help-center/taking-notes/transcription)
- Live transcription is supported: a visible live-transcript panel and "capturing audio" indicator appear during calls — [docs.granola.ai](https://docs.granola.ai/help-center/taking-notes/transcription)
- Pricing (2026): Free/Basic tier, Business $14/user/month, Enterprise $35/user/month; free-tier history limits reported inconsistently across sources — one source says 25 lifetime meetings with 14-day visibility, a more recent source says unlimited meetings but only a rolling 30-day note-access window (older notes retained but locked until upgrade) — [costbench.com](https://costbench.com/software/ai-meeting-assistants/granola/free-plan/), [layer3labs.io](https://www.layer3labs.io/guides/granola-ai-pricing)
- Free Basic plan includes AI meeting notes, AI chat, shared folders, custom templates, multi-language support, and ability to opt out of model training — [costbench.com](https://costbench.com/software/ai-meeting-assistants/granola/)

### Inferences
- Granola's refusal to name its transcription vendor (common pattern in this market — see also Willow Voice, tl;dv) suggests these companies treat ASR as a commoditized, swappable backend and prefer to market their LLM-based summarization/notes layer as the differentiator, not the raw transcription engine.

### Gaps
- Underlying STT vendor for Granola is undisclosed in public docs; no subprocessor list or engineering blog post was found confirming Whisper, Deepgram, AssemblyAI, or a proprietary model.
- No independent WER benchmark specific to Granola was found.

## Otter.ai

### Takeaway
Otter.ai built and operates a proprietary, in-house ASR engine (not a third-party API) and is the top performer in one named independent multi-vendor live-captioning benchmark; pricing is Basic free, Pro $12.99/mo ($8.33/mo annual), Business $30/mo/user ($20/mo/user annual), Enterprise custom.

### Cited Findings
- "Otter.ai architected a proprietary speech recognition engine and developed its own automatic speech recognition (ASR) models instead of relying on third-party APIs"; CTO Yun Fu "architected the proprietary speech recognition engine and cloud infrastructure" — [aiwiki.ai](https://aiwiki.ai/wiki/otter_ai), [thebrandhopper.com](https://thebrandhopper.com/2025/09/09/otter-ai-founders-business-model-funding-competitors/)
- Pricing (2026): Basic free trial/tier; Pro $12.99/mo monthly or $8.33/mo billed annually; Business $30/mo/user monthly or $20/mo/user annually; Enterprise custom — [capterra.com aggregator](https://www.capterra.ca/reviews/202799/otter)
- **Independent benchmark** (Disability World editorial newsroom, published May 22, 2026; test conducted May 4–6, 2026 using NIST sclite scoring against an RPR-certified CART writer at 240 WPM as gold-standard control at 3.1% WER): Otter.ai ranked #1 of 6 live-captioning services tested, at **6.2% WER**, ahead of Google Meet (7.9%), StreamText (8.4%), Microsoft Teams (9.6%), Zoom (11.7%), and Cisco Webex (14.8%). Otter.ai also carries SAS-LIVE certification (Speech-Accessibility Standard for live captioning, ratified 2024) at a published WER floor of 8%. Test used 8 scripted speakers with mixed accents (General American, Received Pronunciation, Indian English, Bulgarian-accented, Singaporean, French-accented, Scottish English) and 17 named entities. Performance by condition: clean US-English ~4.1% WER, mixed-accent ~7.4%, jargon-dense ~8.6%, crosstalk (2–3 speakers) ~42.6% — [disabilityworld.org](https://www.disabilityworld.org/articles/live-caption-accuracy-benchmark/)
- Other reviewer-aggregated figures (methodology undisclosed, treat as directional): "92–94% accuracy on clean audio, 82–85% on real-world meetings, 71–78% in noisy environments, WER range 6–29%" — [aiproductivity.ai aggregator, via search summary]

### Inferences
- The Disability World benchmark is the single most rigorous independent, methodologically-transparent (NIST sclite, certified CART control, disclosed accent panel) head-to-head test found across this entire research scope, and it is directly relevant to Yapperroni's "accents and noisy rooms" question. Its crosstalk result (42.6% WER for 2–3 overlapping speakers, across ALL six vendors, not just Otter) is a strong signal that multi-speaker VC-call audio is the hardest case regardless of vendor, and no live-captioning vendor tested handles it well.

### Gaps
- No confirmation of what underlying model/architecture (e.g., Conformer, RNN-T) powers Otter's proprietary engine beyond "deep learning" and "acoustic model" generalities.

## Fireflies.ai

### Takeaway
Fireflies.ai is commercially integrated with AssemblyAI (and separately with Deepgram) and claims 95% transcription accuracy across 100+ languages; it does not meter transcription minutes, instead metering storage and an "AI credits" pool for summarization features. Pricing: Free, Pro $10/user/mo annual ($18/mo monthly), Business $19/user/mo annual ($29/mo monthly), Enterprise $39/user/mo annual.

### Cited Findings
- Fireflies.ai has a live integration with both AssemblyAI and Deepgram (per integration marketplace listings); AssemblyAI's own marketing lists Fireflies among companies that "choose AssemblyAI to build incredible new AI-powered experiences... based on voice data" — [integrately.com](https://integrately.com/integrations/assemblyai/fireflies-ai), [search summary citing assemblyai.com]
- Fireflies claims "95% accurate transcription across 100+ languages with speaker recognition and auto-language detection" (vendor claim) — [fireflies.ai, via search aggregator]
- Pricing (2026): Free $0; Pro $10/user/mo billed annually ($18/mo monthly); Business $19/user/mo annually ($29/mo monthly); Enterprise $39/user/mo annually — [sonix.ai](https://sonix.ai/resources/fireflies-ai-pricing/), [castmagic.io](https://www.castmagic.io/fr/blog/fireflies-pricing)
- Storage/credit allocation instead of minute metering: Free plan 400 minutes/team storage; Pro 8,000 minutes/seat; Business and Enterprise unlimited storage. Separately, an "AI credits" pool governs summaries/action items/AskFred queries, which "teams running high meeting volumes" can exhaust faster than expected — [affine.pro](https://affine.pro/blog/fireflies-ai-pricing-notes)

### Inferences
- Fireflies most likely uses AssemblyAI (and/or Deepgram) as a backend ASR vendor rather than a fully proprietary model, based on the integration/customer relationship — but this is inferred from marketplace/partner listings, not a direct statement from Fireflies that AssemblyAI is its production transcription backend (it could be using these as optional integrations rather than its core pipeline).

### Gaps
- No primary-source confirmation (Fireflies subprocessor list, privacy policy, or engineering blog) was found explicitly naming AssemblyAI or Deepgram as its core/exclusive transcription backend — the "integration" relationship found via search could reflect downstream customer integrations (e.g., exporting Fireflies transcripts into AssemblyAI-powered workflows) rather than Fireflies' own ASR backend. This is a meaningful ambiguity the report writer should flag as unconfirmed.
- No independent WER benchmark specific to Fireflies was found (only the 95% vendor claim).

## Fathom

### Takeaway
Fathom's free plan includes unlimited recording, storage, and transcription (in 25 languages) for the first 5 calls/month of advanced summaries, monetizing the "intelligence layer" rather than transcription itself; paid tiers are Premium $15/user/mo, Team Edition $19/user/mo, Team Edition Pro $29/user/mo (annual discounts 26–35%). Fathom publishes a subprocessor list but the specific STT vendor was not confirmed in this research pass.

### Cited Findings
- Pricing (2026): Free $0 (unlimited recordings/storage/transcription in 25 languages; first 5 calls/month get advanced summaries); Premium $15/user/mo (unlimited advanced summaries + action items); Team Edition $19/user/mo; Team Edition Pro $29/user/mo; annual billing saves 26–35% — [claap.io](https://claap.io/blog/fathom-pricing), [laxis.com](https://www.laxis.com/blog/fathom-review/)
- "Fathom bills recording and transcription at zero and puts the price on the intelligence layer" — [search aggregator synthesis]
- Fathom maintains a public subprocessor list at trust.fathom.video; its documentation states AI subprocessors "may not train on user data," but Fathom itself "uses de-identified customer data to improve its own proprietary models, with an individual opt-out" — [search summary citing trust.fathom.video and Fathom DPA at fathom.ai/dpa]

### Inferences
- Fathom's "free transcription, paid intelligence" model (also seen partially at Fireflies) indicates STT itself has become a loss-leader/commodity in the VC-call-notetaker segment — the business model differentiation is entirely in LLM-based summarization, not transcription accuracy, which may mean several of these products share similar or identical underlying ASR vendors.

### Gaps
- The specific STT vendor(s) on Fathom's subprocessor list (trust.fathom.video) were not directly fetched/confirmed in this pass — flagged as a direct-source lookup still needed if precise vendor attribution matters.
- No independent WER benchmark specific to Fathom was found.

## tl;dv

### Takeaway
tl;dv claims 96% accuracy / 30+ languages for meeting transcription, with Anthropic confirmed as its downstream AI/summarization partner — but the underlying speech-to-text vendor itself was not disclosed in available sources. Pricing (2026): Free (10 lifetime AI-notes meetings, 10 lifetime Ask-AI queries, unlimited recording/transcription), Pro $29/user/mo, Business $98/user/mo (raised from $59/user/mo on April 21, 2026, a 66% increase), Enterprise custom.

### Cited Findings
- "tl;dv's data goes to their servers for processing, then to Anthropic (their AI partner) for generating summaries and insights" — the specific STT provider for the transcription engine itself "isn't clearly disclosed" — [search aggregator summary]
- Claimed accuracy: "96% for clear English audio," 30 supported languages — [search aggregator summary, original tldv.io source not directly fetched]
- Pricing (2026): Free tier — 13 features, unlimited video recording, unlimited transcription in 30+ languages, email/calendar integrations, mobile app, 10 lifetime AI-notes meetings, 10 lifetime Ask-AI queries; Pro $29/user/mo; Business $98/user/mo (up from $59/user/mo as of April 21, 2026 — a 66.1% price increase); Enterprise on request — [costbench.com](https://costbench.com/software/ai-meeting-assistants/tldv/free-plan/), [costbench.com changelog](https://costbench.com/changelog/tldv-price-increase-2026-04/)

### Inferences
- tl;dv's April 2026 66% price hike on its top tier, concurrent with industry-wide moves toward AI-credit metering (Fireflies) and intelligence-layer monetization (Fathom), suggests underlying LLM/inference costs (not transcription) are the primary driver of 2026 meeting-tool price increases.

### Gaps
- No confirmed STT vendor for tl;dv (Deepgram was searched for specifically but not confirmed as a tl;dv dependency in any primary source found).
- No independent accuracy benchmark for tl;dv was found; 96% figure is an unsourced/vendor-level claim.

## Cluely

### Takeaway
Cluely is a real-time, screen-aware "invisible" meeting-coaching overlay (not a traditional notetaker) priced at Free/Starter, Pro $20/mo, Pro+Undetectability $75/mo, Mobile $8/week — its underlying speech-to-text engine could not be reliably confirmed in this research pass; one search result suggested Google Gemini multimodal, but the source (an unofficial-looking third-party docs page for a "free-cluely" project) is not a credible primary source and should not be treated as fact.

### Cited Findings
- Cluely "runs on your desktop and gives you live coaching and answer suggestions during any kind of virtual meeting or call... listens to the conversation, watches what is on your screen... without joining the meeting as a participant" — [dealroom.co](https://dealroom.co/companies/cluely/), [softwarefinder.com](https://softwarefinder.com/sales-tools/cluely)
- Pricing: Starter free; Pro $20/month; Pro + Undetectability $75/month; Mobile $8/week — [eesel.ai](https://eesel.ai/blog/cluely-pricing)
- Use cases cited: technical job interviews, sales objection-handling calls, proctored online exams — [dupple.com](https://dupple.com/learn/cluely-alternatives)

### Inferences
- Cluely's product design (screen-aware + audio + live suggestion generation) implies it needs very low-latency streaming ASR feeding a fast LLM; but which vendor remains unconfirmed.

### Gaps
- **No credible, primary-sourced confirmation of Cluely's STT engine was found.** The single hit suggesting "Google Gemini" came from an unofficial/unrelated third-party documentation mirror (not Cluely's own site) and should be discarded as unreliable — this is a genuine gap, not a confirmed fact.
- No independent accuracy data for Cluely was found.

---

# Cross-Cutting Synthesis of the Four Key Questions

## Which underlying STT vendors/models do these products use?

### Takeaway
The market splits cleanly into three camps: (1) apps built on proprietary in-house models (Otter.ai, Aqua Voice/Avalon, Wispr Flow/Canto as of Aug 2026), (2) apps built on local, user-controlled Whisper/whisper.cpp or Parakeet inference (MacWhisper, Superwhisper, VoiceInk, Spokenly), and (3) apps that undisclosed/commoditize their backend and market the LLM summarization layer instead (Granola, Willow Voice, tl;dv, likely Fathom and Fireflies, Cluely) — vendor identity for this third group is largely unconfirmed in public sources.

### Cited Findings
- See per-product sections above for full citations. Summary table:
  - **Proprietary in-house model**: Otter.ai (own ASR, confirmed via company sourcing) [aiwiki.ai]; Aqua Voice "Avalon" [capterra/search aggregator]; Wispr Flow "Canto" (as of Aug 2026, 2B params) [vktr.com]
  - **Local Whisper/whisper.cpp or Parakeet, user's own machine**: MacWhisper, Superwhisper (free tier), VoiceInk (default), Spokenly (local tier)
  - **BYOK/optional cloud, user's choice of vendor**: VoiceInk (Groq, OpenAI, Deepgram, ElevenLabs, Speechmatics, Soniox, etc.) [tryvoiceink.com/privacy]; Superwhisper Pro (cloud Whisper Large, BYOK) [getvoibe.com]; Spokenly ("your own API keys" tier)
  - **Undisclosed/unconfirmed backend**: Granola (explicitly declines to name vendor in own docs) [docs.granola.ai]; Willow Voice (undisclosed ASR, confirmed Llama-based formatting layer only); tl;dv (Anthropic confirmed only for summarization, not STT); Fireflies (AssemblyAI/Deepgram integration found but not confirmed as core backend); Fathom (subprocessor list exists at trust.fathom.video but not directly confirmed in this pass); Cluely (no credible source found)

### Inferences
- Vendor non-disclosure is the norm, not the exception, among meeting-notetaker products — likely deliberate, since STT is viewed as a commodity/swappable dependency while the LLM note-generation layer is the actual moat. Yapperroni should expect to never get clean subprocessor confirmation from competitors and should treat silence as a (weak) signal of a third-party cloud API rather than a proprietary model, since companies with genuinely proprietary ASR (Otter, Aqua, Wispr) tend to publicize it as a differentiator.

### Gaps
- Direct subprocessor-list or DPA documents were not fetched for Fathom, Fireflies, Granola, tl;dv, or Cluely — only secondary aggregator summaries. If vendor-level certainty is required, each company's live trust/subprocessor page (e.g., trust.fathom.video) should be fetched directly in a follow-up pass.

## What does each cost, and what is the effective cost per hour of audio for a heavy user?

### Takeaway
Dictation apps cluster around $8–15/month flat-rate unlimited plans (Wispr Flow, Willow, Superwhisper, Aqua, Spokenly) or one-time local-compute purchases ($39.99–$249.99, MacWhisper/VoiceInk/Superwhisper lifetime) with near-zero marginal cost per hour once purchased; meeting notetakers run $10–39/user/month with increasingly common "unlimited transcription, metered AI" models (Fireflies credits, Fathom free-transcription-paid-summaries) rather than per-minute billing, making true "cost per hour of audio" difficult to compute directly from list price for a heavy user — it is effectively flat/subscription-capped in most of these consumer products, unlike raw cloud STT APIs (e.g., Deepgram Nova-3 at $0.0048/min ≈ $0.29/hour for streaming transcription alone).

### Cited Findings
- Flat monthly/unlimited dictation pricing: Wispr Flow Pro $12–15/mo; Willow Individual $12–15/mo; Superwhisper Pro $8.49/mo or $84.99/yr; Aqua Voice Pro $8–12.99/mo; Spokenly Pro $8.33–9.99/mo — all effectively unlimited word/usage once subscribed (see per-product sections for exact figures and sources).
- One-time local-compute purchases: MacWhisper Pro $69 one-time (Pro Max $149); VoiceInk $39.99 one-time (or free/open-source); Superwhisper Lifetime $249.99 (breakeven vs. monthly at ~month 29, vs. annual at ~year 3) — [getvoibe.com](https://www.getvoibe.com/resources/superwhisper-pricing/)
- Meeting notetakers: Granola Free/$14/user/mo (Business)/$35/user/mo (Enterprise); Otter.ai Free/$12.99 (Pro)/$30 (Business) per user/mo; Fireflies Free/$10 (Pro, annual)/$19 (Business, annual)/$39 (Enterprise, annual) per user/mo, metered by storage+AI credits not minutes; Fathom Free (unlimited transcription)/$15 (Premium)/$19/$29 per user/mo, transcription itself free even on paid tiers; tl;dv Free/$29 (Pro)/$98 (Business, up from $59 in April 2026) per user/mo; Cluely Free/$20 (Pro)/$75 (Pro+Undetectability)/mo or $8/week (Mobile).
- Raw cloud STT API pricing for comparison: Deepgram Nova-3 streaming from $0.0048/minute (~$0.29/hour), with $200 free credit; Deepgram's bundled Voice Agent API (STT+TTS+logic) costs $0.075/minute (~$4.50/hour) — [happyrobot.ai](https://www.happyrobot.ai/hub/deepgram-pricing), [dailyaifixs.com](https://dailyaifixs.com/blog/deepgram-pricing-2026-the-sub-cent-myth)

### Inferences
- For a heavy user (e.g., 40+ hours/month of dictation or meetings), nearly every consumer product in this list is cheaper via flat subscription than building on a raw cloud STT API would be if the API were billed per-minute at consumer-facing margins — e.g., 40 hours/month at Deepgram's raw $0.0048/min list rate is only ~$11.52, implying the $10–39/seat subscription prices charged by Fireflies/Otter/tl;dv embed a large markup over raw transcription cost, consistent with the finding that these companies monetize the "intelligence layer," not transcription.
- This strongly favors Yapperroni building on local/on-device STT (zero marginal cost, matches MacWhisper/VoiceInk/Superwhisper's free-tier model) or a cheap pass-through cloud API (Deepgram-class, sub-$0.01/min) rather than assuming it must charge enough to cover a premium per-minute vendor like AssemblyAI/Rev at retail rates.

### Gaps
- No vendor in this research discloses its actual wholesale STT cost (only Deepgram's public list price was found as a reference raw-API rate); actual margin structure for Otter/Fireflies/Fathom/tl;dv is not derivable from public data.

## What is the evidence for accuracy, especially for accents and noisy rooms? Vendor claims vs. independent tests.

### Takeaway
The only rigorous, disclosed-methodology independent test found that specifically targets accents and noisy/crosstalk conditions is the Disability World live-captioning benchmark (May 2026), which found Otter.ai best among 6 live-captioning vendors at 6.2% WER overall but showed WER spiking to ~42.6% for all vendors under 2–3 speaker crosstalk — i.e., even the best vendor degrades sharply in exactly the multi-speaker VC-call scenario Yapperroni targets. Most other "accuracy" figures in this space are vendor-published or competitor-published marketing claims without disclosed methodology.

### Cited Findings
- See Otter.ai section: Disability World benchmark (May 22, 2026) — NIST sclite scoring, RPR-certified CART control at 3.1% WER gold standard, 8 scripted speakers across 7 accent types, 3× 60-minute sessions. Results: Otter.ai 6.2%, Google Meet 7.9%, StreamText 8.4%, MS Teams 9.6%, Zoom 11.7%, Cisco Webex 14.8%. By condition: clean US-English ~4.1%, mixed-accent ~7.4%, jargon-dense ~8.6%, **crosstalk (2–3 speakers) ~42.6%** — [disabilityworld.org](https://www.disabilityworld.org/articles/live-caption-accuracy-benchmark/)
- Superwhisper's self-published 8-dataset, 16-system benchmark (includes Common Voice Australian English and "spontaneous English" as accent/naturalness proxies, plus AMI Meetings as a noisy/multi-speaker proxy) is the broadest multi-vendor comparison found, but is vendor-published by a direct competitor to several products it ranks — [superwhisper.com/benchmarks/wispr-flow-raw](https://superwhisper.com/benchmarks/wispr-flow-raw)
- Vendor-only claims (no disclosed methodology, should be weighted lowest): Wispr Flow Canto ">30% to ~5–10% WER" in difficult conditions [vktr.com]; Fireflies "95% accurate... 100+ languages" [fireflies.ai]; tl;dv "96% for clear English audio" [search aggregator]; Aqua Voice Avalon "#1 on OpenASR leaderboard" (leaderboard not independently verified in this pass) [aggregator].
- Competitor-vs-competitor marketing claims (lowest reliability — both self-interested): LumeVoice claims 1.2% WER beating Wispr Flow's 2.1% [lumevoice.com]; getvoibe.com aggregator claims legacy Apple Dictation 75–85% accuracy vs. Whisper 95–97% [getvoibe.com].

### Inferences
- The single most load-bearing independent datapoint for Yapperroni's "noisy rooms / multi-speaker VC calls" use case is the Disability World crosstalk result: ~42.6% WER across ALL vendors tested when 2–3 speakers overlap. This suggests that no commercial live-transcription vendor (including Otter.ai, the best performer) has solved overlapping speech well, and that Yapperroni's competitive opportunity/risk is identical to incumbents' weakest point, not a solved problem it needs to merely match.
- Accent-specific degradation is real but more modest than crosstalk: the same benchmark shows mixed-accent WER (~7.4%) less than 2x clean-English WER (~4.1%), while crosstalk WER is ~10x clean. This suggests Yapperroni's engineering priority for "accuracy in real conditions" should weight overlapping-speaker handling (diarization/separation) above raw accent robustness.

### Gaps
- No independent benchmark was found that tests any of the *dictation* apps (Wispr Flow, Superwhisper, MacWhisper, Aqua, Willow, VoiceInk, Spokenly) specifically on accented speech or noisy-room conditions with disclosed methodology — the Disability World benchmark covers meeting/live-captioning platforms (Otter, Teams, Zoom, Webex, Google Meet, StreamText) only, not the dictation-app category.
- No independent benchmark covering Fireflies, Fathom, tl;dv, Granola, or Cluely directly was found (only Otter.ai among meeting notetakers appears in the one rigorous independent test located).

## Apple SpeechAnalyzer/SpeechTranscriber on macOS 26: independent accuracy and speed vs. Whisper large-v3-turbo

### Takeaway
Two independently-sourced benchmarks (MacGeneration reporting on an "Inscribe" developer benchmark, and a dev.to post by the maker of "IraVoice") both find Apple's new macOS 26 SpeechAnalyzer/SpeechTranscriber framework beats Whisper **Small** by roughly 2x on WER (clean LibriSpeech: ~2% Apple vs. ~3.7–4.3% Whisper Small) and runs meaningfully faster — but **neither benchmark tested Whisper large-v3-turbo**, which is a substantially stronger model than Whisper Small. This is the single most important gap in available evidence for Yapperroni's specific question.

### Cited Findings
- MacG/Inscribe benchmark (July 14, 2026): SpeechAnalyzer 2.12% WER clean / 4.56% noisy vs. Whisper **Small** 3.74% / 7.95%; legacy SFSpeechRecognizer 9.02% / 16.25%. 5,559 LibriSpeech excerpts, English only, M2 Pro/32GB, macOS 26.5.1, local-only. "Approximately three times faster" for batch processing — [macg.co](https://www.macg.co/macos/2026/07/speechanalyzer-un-benchmark-confirme-que-la-transcription-dapple-bat-le-whisper-dopenai-309741)
- IraVoice/dev.to benchmark: Apple SpeechAnalyzer 1.98% WER / 1.02% CER vs. whisper.cpp ggml-**small.en** 4.28% WER / 1.79% CER, on LibriSpeech test-clean, 40 speakers, M5 Max/128GB, macOS 26.5. Streaming latency was comparable between the two engines (Apple 125–132ms median vs. whisper.cpp 122–125ms median) — i.e., the "faster" claim applies to batch/offline throughput, not necessarily to streaming latency — [dev.to/iravoice](https://dev.to/iravoice/apple-speechanalyzer-vs-whispercpp-a-40-speaker-mac-benchmark-40i4)
- Both tests are English-only, read-speech (LibriSpeech), not conversational/accented/meeting audio.
- SpeechTranscriber covers ~30 languages/locales vs. Whisper's 99+, and requires macOS 26+ / modern Apple Silicon, while Whisper runs cross-platform — [search aggregator synthesis]

### Inferences
- Because both available benchmarks compare against Whisper Small rather than large-v3-turbo, the finding "Apple beats Whisper" cannot be extended to Yapperroni's actual likely baseline model (large-v3-turbo is generally regarded as meaningfully more accurate than Small, roughly matching or approaching large-v3 at much faster speed). It is plausible — but not evidenced by anything found in this research — that large-v3-turbo closes most or all of the WER gap with SpeechAnalyzer while still being slower and requiring more compute. Yapperroni should treat "Apple beats Whisper" as true only for the Small-vs-SpeechAnalyzer comparison, and should run its own large-v3-turbo comparison (e.g., reusing the LibriSpeech test-clean set both existing benchmarks used, for direct comparability) before deciding.
- The consistent ~3x batch-speed advantage and free/on-device/no-API-cost nature of SpeechAnalyzer is independently attractive for a macOS-only product regardless of the large-v3-turbo accuracy question, since it eliminates both cloud cost and privacy exposure for English-language users on macOS 26+.

### Gaps
- **No benchmark comparing Apple SpeechAnalyzer directly to Whisper large-v3-turbo was found anywhere in this research pass** — this is the most important actionable gap for Yapperroni and should be called out explicitly to the report writer/decision-maker.
- No benchmark of SpeechAnalyzer on non-English languages, accented English, or multi-speaker meeting audio was found.
