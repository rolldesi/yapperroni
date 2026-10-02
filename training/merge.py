"""Fold a LoRA adapter into turbo and save a plain Hugging Face checkpoint,
which whisper.cpp's converters take as input.

    python merge.py --adapter runs/x/checkpoints/best/adapter --out out/name/hf
    python merge.py --adapter base --out out/name/hf     # unmodified turbo

`--adapter hf:you/repo` pulls checkpoints/best from the store.
"""
import argparse

import model as M


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adapter", required=True)
    ap.add_argument("--base", default=M.BASE)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    import torch
    from transformers import WhisperForConditionalGeneration, WhisperProcessor
    model = WhisperForConditionalGeneration.from_pretrained(a.base, dtype=torch.float32)
    if a.adapter != "base":
        from peft import PeftModel
        path = a.adapter
        if path.startswith("hf:"):
            from store import Store
            s = Store(path)
            s.pull("checkpoints/best")
            path = str(s.path("checkpoints/best/adapter"))
        model = PeftModel.from_pretrained(model, path).merge_and_unload()
    model.save_pretrained(a.out)
    WhisperProcessor.from_pretrained(a.base).save_pretrained(a.out)
    # whisper.cpp's converter reads the slow-tokenizer files, which current
    # transformers no longer writes on save. Take them from the base repo.
    import shutil
    from huggingface_hub import hf_hub_download
    for f in ["vocab.json", "added_tokens.json", "merges.txt", "normalizer.json",
              "special_tokens_map.json", "preprocessor_config.json"]:
        shutil.copy(hf_hub_download(a.base, f), f"{a.out}/{f}")
    print(f"merged model saved to {a.out}")


if __name__ == "__main__":
    main()
