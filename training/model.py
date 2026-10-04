"""Whisper, LoRA, batching — shared by prepare.py, train.py and export."""
import numpy as np
import torch
from transformers import WhisperForConditionalGeneration, WhisperProcessor

BASE = "openai/whisper-large-v3-turbo"
# Attention and MLP in both halves. The encoder is where accents and rooms
# live; leaving it frozen (--decoder-only) is cheaper but only adapts
# vocabulary and style.
LORA_TARGETS = ["q_proj", "k_proj", "v_proj", "out_proj", "fc1", "fc2"]


def device_and_dtype(prefer: str = "auto"):
    if prefer == "cpu":
        return torch.device("cpu"), torch.float32
    if torch.cuda.is_available():
        # T4 and P100 have no bf16; fp16 with a GradScaler is the path there.
        bf16 = torch.cuda.is_bf16_supported()
        return torch.device("cuda"), (torch.bfloat16 if bf16 else torch.float16)
    if torch.backends.mps.is_available():
        # Measured on an M5 (turbo, LoRA, batch 4): bf16 is 2.6 clips/s
        # against 1.0 in fp32 decoder-only, and 0.31 against 0.20 with the
        # encoder trained too. No GradScaler needed: bf16 has fp32's range.
        return torch.device("mps"), torch.bfloat16
    return torch.device("cpu"), torch.float32


def load(name: str, device, dtype):
    from transformers.utils import logging as hf_logging
    hf_logging.set_verbosity_error()  # generate() warns on every batch otherwise
    processor = WhisperProcessor.from_pretrained(name)
    model = WhisperForConditionalGeneration.from_pretrained(name, dtype=dtype).to(device)
    model.config.use_cache = False
    return processor, model


def add_lora(model, r: int, decoder_only: bool):
    from peft import LoraConfig, get_peft_model
    targets = LORA_TARGETS
    if decoder_only:
        targets = r"model\.decoder\..*\.(" + "|".join(LORA_TARGETS) + r")"
    cfg = LoraConfig(r=r, lora_alpha=2 * r, lora_dropout=0.05, target_modules=targets, bias="none")
    return get_peft_model(model, cfg)


def features(processor, audios: list[np.ndarray], device, dtype) -> torch.Tensor:
    f = processor.feature_extractor(audios, sampling_rate=16_000, return_tensors="pt").input_features
    return f.to(device=device, dtype=dtype)


def labels(processor, texts: list[str], langs: list[str]) -> torch.Tensor:
    """Token ids as whisper is prompted at inference: start, language,
    transcribe, no-timestamps, text, end. The model prepends the start token
    itself when shifting, so it is stripped here."""
    tok = processor.tokenizer
    rows = []
    for text, lang in zip(texts, langs):
        tok.set_prefix_tokens(language=lang, task="transcribe", predict_timestamps=False)
        ids = tok(text).input_ids
        if ids and ids[0] == tok.convert_tokens_to_ids("<|startoftranscript|>"):
            ids = ids[1:]
        rows.append(ids[:440])
    width = max(len(r) for r in rows)
    out = torch.full((len(rows), width), -100, dtype=torch.long)
    for i, r in enumerate(rows):
        out[i, : len(r)] = torch.tensor(r)
    return out


@torch.no_grad()
def transcribe(model, processor, audios: list[np.ndarray], lang: str, device, dtype,
               batch: int = 16) -> list[str]:
    """Greedy, no timestamps — the same decoding the app runs."""
    was_training = model.training
    model.eval()
    out = []
    for i in range(0, len(audios), batch):
        feats = features(processor, audios[i:i + batch], device, dtype)
        # use_cache=True overrides the config: training turns the cache off,
        # and without it every new token re-runs the decoder over all the
        # ones before it — the step-0 eval had not finished 600 clips after
        # eleven minutes, and the GPU memory pool grew until macOS killed it.
        ids = model.generate(input_features=feats, language=lang, task="transcribe",
                             return_timestamps=False, max_new_tokens=440, use_cache=True)
        out += [t.strip() for t in processor.batch_decode(ids, skip_special_tokens=True)]
    if was_training:
        model.train()
    return out
