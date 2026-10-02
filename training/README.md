# Training

LoRA fine-tune of Whisper large-v3-turbo for lectures, online classes and
meetings — French-accented English especially — on free Kaggle and Colab
GPUs, then back into Yapperroni as a model the pickers list.

Nothing here has been trained yet. Everything has been run end to end on this
Mac with `whisper-tiny` on 120 real AMI rows (`smoke/run.sh`); the speed and
memory of the real run are unknown until the first hour on a T4.

## How a run moves between Kaggle and Colab

One training run, handed back and forth. Every 30 minutes, and before the
session's 12-hour limit, `train.py` writes the LoRA adapter, optimizer,
schedule, epoch and the exact position in the data stream to a private
Hugging Face repo. A new session on either platform pulls the latest and
continues from the same step and the same row. With Weights & Biases on, the
whole run is one chart however many sessions it takes.

## Setup (once)

1. Hugging Face account → *Settings → Access tokens* → a **write** token.
   The repo `yourname/yapperroni-train` is created private on first use.
2. Optional: Weights & Biases account → API key from wandb.ai/authorize.
3. On Kaggle and on Colab, add secrets `HF_TOKEN` and `WANDB_API_KEY`.
4. Upload `yapperroni_train.ipynb`, set `HF_USER` in its second cell, choose a
   T4 GPU (Kaggle: also turn Internet on).

## Running

| Step | Notebook cell | What it does | Stops and resumes |
|---|---|---|---|
| 1 | `prepare.py` | base turbo transcribes AMI's headset clips once; human words get turbo's casing and punctuation | every 2,000 rows |
| 2 | `train.py` | LoRA training; scores unmodified turbo at step 0, then every 500 steps | every 30 min + before the limit |

Re-run whichever cell you are on in each new session, on either platform.

## Back into Yapperroni (on this Mac)

    ./export.sh hf:yourname/yapperroni-train          # best checkpoint
    ./export.sh base roundtrip-turbo                  # unmodified turbo: the conversion check

It merges the adapter, converts to whisper.cpp, quantizes to q5_0, builds
the Neural Engine encoder, and copies both into the support folder. Keep the
new model only if it beats turbo on the three MIT classes (8.6% average) —
score it with the app's own `--selftest-whisper`, which runs the exact
decoding Yapperroni uses.

## Data

| Source | Use | Hours | Licence |
|---|---|---|---|
| AMI, far-field (sdm) + headset (ihm) | train | ~100 | CC BY 4.0 |
| VoxPopuli English | train, on its own (already punctuated) text | ~540 | CC0 |
| VoxPopuli French | train, 10% of the mix | — | CC0 |
| VoxPopuli accented, French speakers | **test only** | 2.6 | CC0 |
| AMI far-field test split | **test only** | — | CC BY 4.0 |
| Earnings-22 | **test only** | — | CC BY-SA 4.0 |

All streamed from the Hugging Face Parquet mirrors; nothing downloads whole.
Only public data is used. Your own recordings need participants' consent that
covers cloud processing, and belong in a separate, deliberate step.

## Why transcripts are rewritten before training

AMI is ALL CAPS with no punctuation ("IF YOU IF YOU S. S. H."). Trained on
as-is, turbo learns to write that way, and
WER cannot show it because scoring strips case and punctuation. `prepare.py`
keeps the human's words and borrows casing and punctuation from turbo's own
transcript of the same audio (`text.restore_style`), and every eval reports
the share of punctuated outputs next to WER so that regression is visible.

## Judging a trained model

Compare it against `./export.sh base roundtrip-turbo`, built with the same
toolchain — not against the downloaded turbo. Today the two are word-for-word
identical on two ten-minute MIT lectures, but a whisper.cpp or coremltools
update could change the conversion, and the baseline has to move with it.

How the encoder runs alone moves a ten-minute score by about a point: the
same weights scored 7.6% (published Neural Engine encoder), 8.4% (a plain
conversion) and 9.0% (GPU only) on the Duflo lecture. A gain under a point
on a single clip is noise; look for it across all three classes.

## Known limits

- **Tested on this Mac only, with whisper-tiny.** A T4 runs fp16 with a
  GradScaler; an A100 (Colab Pro) takes the bf16 branch, which nothing has
  run through yet. The first session on each will show if it works.
- **Resume is close to exact, not exact.** Up to one partial batch (< 8 clips)
  is skipped at each resume, and the 500-clip shuffle buffer refills, so a
  few hundred clips are seen again. Negligible against an epoch.
- **A session killed during eval loses back to the last save** (≤ 30 min).
  Eval is 3 × `--eval-n` clips; lower it to shorten that window.
- **The first stream of each VoxPopuli shard reads a ~700 MB chunk** before
  its first row (47 s here, faster on cloud bandwidth).
- **Restored AMI text keeps AMI's spellings where turbo disagrees:** spelled-out
  letters ("s. s. h.") and spelled-out numbers ("twenty twenty"). The scorer
  ignores numbers, so whether the model learns to spell them out is not
  measured.

## Files

| File | Role |
|---|---|
| `text.py` | scoring normalizer, WER, punctuation stats, `restore_style` (`python text.py` self-checks) |
| `data.py` | sources, streaming, audio decoding, the mix, eval sets |
| `model.py` | turbo + LoRA, labels with per-row language prefix, batched transcription |
| `store.py` | local folder or private HF repo |
| `prepare.py` / `train.py` | the two steps |
| `merge.py` / `export.sh` | adapter → Yapperroni model |
| `make_notebook.py` | builds `yapperroni_train.ipynb` from the files above |
| `smoke/run.sh` | the end-to-end local test |
