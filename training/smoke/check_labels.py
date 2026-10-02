"""Decode a batch of training labels back to text: the language prefix must
be right per row, or French rows would train as English."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import model as M  # noqa: E402
from transformers import WhisperProcessor  # noqa: E402

p = WhisperProcessor.from_pretrained(sys.argv[1] if len(sys.argv) > 1 else "openai/whisper-tiny")
lab = M.labels(p, ["Hello there.", "Bonjour à tous."], ["en", "fr"])
fails = 0
for row, want in zip(lab.tolist(), ["<|en|><|transcribe|><|notimestamps|>Hello there.<|endoftext|>",
                                    "<|fr|><|transcribe|><|notimestamps|>Bonjour à tous.<|endoftext|>"]):
    got = p.tokenizer.decode([t for t in row if t != -100])
    ok = got == want
    fails += not ok
    print(f"  {'ok  ' if ok else 'FAIL'} {got}")
print("PASS" if not fails else f"FAIL: {fails}")
sys.exit(1 if fails else 0)
