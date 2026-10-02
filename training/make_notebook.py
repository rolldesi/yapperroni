"""Builds yapperroni_train.ipynb from the modules in this folder, so the
notebook uploaded to Kaggle or Colab is always the code the smoke test ran.

    python make_notebook.py
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULES = ["text.py", "data.py", "model.py", "store.py", "prepare.py", "train.py", "requirements.txt"]


def md(s):
    return {"cell_type": "markdown", "metadata": {}, "source": s.strip("\n").splitlines(keepends=True)}


def code(s):
    return {"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [],
            "source": s.strip("\n").splitlines(keepends=True)}


cells = [
    md("""
# Yapperroni — fine-tune whisper turbo for lectures and meetings

One notebook for **Kaggle and Colab**. Everything that matters between sessions
(restored transcripts, checkpoints, test clips) lives in your private Hugging
Face repo, so a run started on one platform continues on the other.

**Before the first run**
1. Hugging Face: create a *write* token at huggingface.co/settings/tokens.
2. Optional, Weights & Biases: copy your API key from wandb.ai/authorize.
3. Add them as secrets named `HF_TOKEN` and `WANDB_API_KEY`
   — Kaggle: *Add-ons → Secrets*. Colab: the key icon in the left bar.
4. Kaggle: *Settings → Accelerator: GPU T4 x2* and *Internet: on*. Colab: *Runtime → Change runtime type → T4 GPU*.
5. Set `HF_USER` in the next cell.

**Order of work** — each step stops by itself before the session limit and
continues where it left off when you run it again, on either platform:
1. `prepare.py` — one pass of base turbo over AMI to repair its style (ALL CAPS, no punctuation).
2. `train.py` — LoRA training. Step 0 scores unmodified turbo: that is the number to beat.

**Memory on a free T4 (16 GB)** — starting points, not measurements: turbo in fp16 ≈ 1.6 GB,
LoRA r=32 adds ~100 MB of trainable weights, gradient checkpointing is on. If you hit
out-of-memory, halve `--batch` and double `--accum`. The first hour's log line
`s-audio/s` is the real speed; everything else is an estimate until then.

Only public datasets are used here. Training on your own recordings belongs in a separate,
clearly consented step — it is deliberately not in this notebook.
"""),
    code("""
HF_USER = "your-hf-username"          # <- change this
STORE = f"hf:{HF_USER}/yapperroni-train"
WANDB_PROJECT = "yapperroni"          # "" to skip Weights & Biases

import os
def secret(name):
    try:
        from kaggle_secrets import UserSecretsClient          # Kaggle
        return UserSecretsClient().get_secret(name)
    except Exception:
        pass
    try:
        from google.colab import userdata                     # Colab
        return userdata.get(name)
    except Exception:
        return os.environ.get(name)

os.environ["HF_TOKEN"] = secret("HF_TOKEN") or ""
if WANDB_PROJECT:
    os.environ["WANDB_API_KEY"] = secret("WANDB_API_KEY") or ""
WANDB_ARG = f"--wandb {WANDB_PROJECT}" if WANDB_PROJECT and os.environ.get("WANDB_API_KEY") else ""
assert os.environ["HF_TOKEN"], "add an HF_TOKEN secret (a write token) first"
platform = "kaggle" if os.path.exists("/kaggle") else "colab" if "COLAB_RELEASE_TAG" in os.environ else "local"
print("platform:", platform, "| store:", STORE, "| wandb:", bool(WANDB_ARG))
"""),
]
for m in MODULES:
    # Not through code(): stripping would drop the file's final newline.
    cells.append({"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [],
                  "source": (f"%%writefile {m}\n" + (HERE / m).read_text()).splitlines(keepends=True)})
cells += [
    code("""
!pip install -q -r requirements.txt
!nvidia-smi --query-gpu=name,memory.total --format=csv
!python text.py
"""),
    md("""
## Step 1 — repair transcript style (run until every source says complete)
Roughly a few GPU-hours in total; it saves every 2,000 rows. Re-run this cell in a new
session to continue.
"""),
    code("""
!python prepare.py --store {STORE} --max-hours 11
"""),
    md("""
## Step 2 — train
Re-run in each new session, on Kaggle or Colab: it resumes from the latest checkpoint
in the store. Watch `eval step …` lines (or W&B): mean WER should fall below step 0,
and `punct` should stay near 100%.
"""),
    code("""
!python train.py --store {STORE} --max-hours 11.5 {WANDB_ARG}
"""),
]

for i, c in enumerate(cells):
    c["id"] = f"cell-{i:02d}"
nb = {"cells": cells, "metadata": {"kernelspec": {"name": "python3", "display_name": "Python 3"},
                                   "language_info": {"name": "python"}, "accelerator": "GPU"},
      "nbformat": 4, "nbformat_minor": 5}
(HERE / "yapperroni_train.ipynb").write_text(json.dumps(nb, indent=1))
print("wrote yapperroni_train.ipynb with", len(cells), "cells")
