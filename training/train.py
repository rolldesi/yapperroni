"""LoRA fine-tune of whisper turbo, resumable across Kaggle and Colab sessions.

Every `--save-minutes` and before `--max-hours` runs out, the adapter, the
optimizer, the schedule and the exact stream position go to the store; a new
session on either platform pulls the latest and carries on from the same
step and the same row. Eval runs at step 0 — the number to beat — and every
`--eval-every` steps on clips that are never trained on.

    python train.py --store hf:you/yapperroni-train
"""
import argparse
import contextlib
import json
import os
import random
import signal
import tempfile
import time
from pathlib import Path

import numpy as np
import pyarrow.parquet as pq
import torch

import data
import model as M
import text
from store import Store


def load_targets(store: Store, names: set[str]) -> dict[str, dict[str, str]]:
    out = {}
    for n in names:
        store.pull(f"targets/{n}")
        parts = sorted(store.path(f"targets/{n}").glob("part-*.parquet"))
        table = {}
        for p in parts:
            t = pq.read_table(p).to_pydict()
            table.update(zip(t["key"], t["text"]))
        out[n] = table
        print(f"targets {n}: {len(table)} restored transcripts")
    return out


def load_eval(store: Store, names: list[str], n: int, local: dict) -> dict[str, list[dict]]:
    """Cached in the store after the first build, so every session scores the
    very same clips and none of them re-streams a 2 GB shard to find them."""
    sets = {}
    for name in names:
        sub = f"eval/{name}-{n}.npz"
        if store.pull(sub):
            # Plain arrays, no pickle: the cache comes back from a remote repo.
            z = np.load(store.path(sub), allow_pickle=False)
            cuts = np.cumsum(z["lengths"])[:-1]
            sets[name] = [{"audio": x, "text": str(t), "lang": str(z["lang"])}
                          for x, t in zip(np.split(z["audio"], cuts), z["texts"])]
        else:
            rows = data.eval_rows(name, n, local.get(name))
            store.path("eval").mkdir(parents=True, exist_ok=True)
            np.savez(store.path(sub), audio=np.concatenate([r["audio"] for r in rows]),
                     lengths=np.array([len(r["audio"]) for r in rows]),
                     texts=np.array([r["text"] for r in rows]), lang=np.array(rows[0]["lang"]))
            store.push(sub)
            sets[name] = rows
        print(f"eval {name}: {len(sets[name])} clips")
    return sets


def evaluate(model, processor, sets, device, dtype, amp) -> dict:
    res = {}
    with amp():
        for name, rows in sets.items():
            hyps = M.transcribe(model, processor, [r["audio"] for r in rows], rows[0]["lang"],
                                device, dtype, batch=8)
            res[name] = {"wer": text.wer([r["text"] for r in rows], hyps), **text.style_stats(hyps)}
    res["mean_wer"] = float(np.mean([v["wer"] for v in res.values()]))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", required=True)
    ap.add_argument("--model", default=M.BASE)
    ap.add_argument("--mix", default=",".join(f"{k}={v}" for k, v in data.DEFAULT_MIX.items()))
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--accum", type=int, default=4)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--warmup", type=int, default=200)
    ap.add_argument("--max-steps", type=int, default=6000)
    ap.add_argument("--lora-r", type=int, default=32)
    ap.add_argument("--decoder-only", action="store_true")
    ap.add_argument("--eval-every", type=int, default=500)
    ap.add_argument("--eval-n", type=int, default=200)
    ap.add_argument("--save-minutes", type=float, default=30)
    ap.add_argument("--max-hours", type=float, default=11.5)
    ap.add_argument("--raw-targets", action="store_true",
                    help="train on unrestored transcripts (teaches ALL CAPS, no punctuation)")
    ap.add_argument("--device", default="auto")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--local", default="", help="source=file.parquet,... (smoke test)")
    ap.add_argument("--wandb", default="", help="W&B project name; needs WANDB_API_KEY")
    a = ap.parse_args()

    started = time.time()
    store = Store(a.store)
    local = {k: [v] for k, v in (p.split("=") for p in a.local.split(",") if p)}
    mix = {k: float(v) for k, v in (p.split("=") for p in a.mix.split(","))}
    device, dtype = M.device_and_dtype(a.device)
    amp = (lambda: torch.autocast("cuda", dtype=dtype)) if device.type == "cuda" else contextlib.nullcontext
    print(f"device {device} {dtype}")

    processor, model = M.load(a.model, device, dtype)
    model = M.add_lora(model, a.lora_r, a.decoder_only)
    model.base_model.model.gradient_checkpointing_enable(gradient_checkpointing_kwargs={"use_reentrant": False})
    model.print_trainable_parameters()
    params = [p for p in model.parameters() if p.requires_grad]
    opt = torch.optim.AdamW(params, lr=a.lr, weight_decay=0.01)
    from transformers import get_cosine_schedule_with_warmup
    sched = get_cosine_schedule_with_warmup(opt, a.warmup, a.max_steps)
    scaler = torch.amp.GradScaler("cuda", enabled=(dtype == torch.float16))

    epoch, wandb_id = 0, None
    stream = data.mixed(mix, a.seed, local)
    step, best, history = 0, float("inf"), []
    if store.pull("checkpoints/latest/meta.json"):
        store.pull("checkpoints/latest")
        ck = store.path("checkpoints/latest")
        meta = json.loads((ck / "meta.json").read_text())
        from peft import set_peft_model_state_dict
        from safetensors.torch import load_file
        set_peft_model_state_dict(model, load_file(ck / "adapter" / "adapter_model.safetensors"))
        tr = torch.load(ck / "trainer.pt", map_location="cpu", weights_only=True)
        opt.load_state_dict(tr["opt"]); sched.load_state_dict(tr["sched"]); scaler.load_state_dict(tr["scaler"])
        random.setstate(tr["py_rng"]); torch.set_rng_state(tr["torch_rng"])
        epoch = meta.get("epoch", 0)
        wandb_id = meta.get("wandb_id")
        stream = data.mixed(mix, a.seed + epoch, local)
        stream.load_state_dict(meta["stream"])
        step, best, history = meta["step"], meta["best"], meta["history"]
        print(f"resumed at step {step} (best mean WER {best:.4f})")

    # One W&B run for the whole training, however many sessions and platforms
    # it takes: its id rides in the checkpoint and every session resumes it.
    wb = None
    if a.wandb:
        import wandb
        wandb_id = wandb_id or __import__("uuid").uuid4().hex[:12]
        wb = wandb.init(project=a.wandb, id=wandb_id, resume="allow", config=vars(a),
                        name=f"turbo-lora-r{a.lora_r}")

    def log(d: dict):
        if wb:
            wb.log(d, step=step)

    targets = {} if a.raw_targets else load_targets(
        store, {data.TARGETS_FROM.get(n, n) for n in mix if data.TRAIN[n].restore})
    evals = load_eval(store, list(data.EVAL), a.eval_n, local)

    def save(why: str, metrics: dict | None = None):
        nonlocal best
        stage = Path(tempfile.mkdtemp(prefix="ckpt-"))
        model.save_pretrained(stage / "adapter")
        torch.save({"opt": opt.state_dict(), "sched": sched.state_dict(), "scaler": scaler.state_dict(),
                    "py_rng": random.getstate(), "torch_rng": torch.get_rng_state()}, stage / "trainer.pt")
        improved = metrics is not None and metrics["mean_wer"] < best
        if improved:
            best = metrics["mean_wer"]
        (stage / "meta.json").write_text(json.dumps(
            {"step": step, "epoch": epoch, "best": best, "history": history, "stream": stream.state_dict(),
             "wandb_id": wandb_id,
             "args": vars(a)}, default=str))
        if improved:
            import shutil
            shutil.copytree(stage, stage.parent / (stage.name + "-best"))
            store.replace_dir("checkpoints/best", stage.parent / (stage.name + "-best"))
        store.replace_dir("checkpoints/latest", stage)
        print(f"saved step {step} ({why}){' — new best' if improved else ''}", flush=True)

    def run_eval():
        m = evaluate(model, processor, evals, device, dtype, amp)
        history.append({"step": step, **m})
        log({"eval/mean_wer": m["mean_wer"], **{f"eval/{k}/{f}": v[f] for k, v in m.items()
                                                 if isinstance(v, dict) for f in v if v[f] is not None}})
        print("eval step %d: " % step + "  ".join(
            f"{k} {v['wer']*100:.1f}% (punct {v['punctuated'] if v['punctuated'] is None else round(v['punctuated']*100)}%)"
            for k, v in m.items() if k != "mean_wer") + f"  | mean {m['mean_wer']*100:.2f}%", flush=True)
        return m

    stop = {"now": False}
    signal.signal(signal.SIGTERM, lambda *_: stop.update(now=True))
    deadline = started + a.max_hours * 3600
    last_save = time.time()

    if step == 0:
        save("baseline", run_eval())

    def rows():
        # One pass over the mix is an epoch; the next one reshuffles. The
        # epoch is part of the checkpoint so resume lands in the right pass.
        nonlocal stream, epoch
        while True:
            yield from stream
            epoch += 1
            print(f"epoch {epoch} begins", flush=True)
            stream = data.mixed(mix, a.seed + epoch, local)

    model.train()
    batch, micro, audio_secs, missing, t_log = [], 0, 0.0, 0, time.time()
    for row in rows():
        name = row["source"]
        src = data.TRAIN[name]
        if a.raw_targets or not src.restore:
            target = row["human"]
        else:
            target = targets[data.TARGETS_FROM.get(name, name)].get(row["key"])
            if target is None:
                missing += 1
                continue
        x = data.decode(row["audio"])
        if x is None or not target:
            continue
        batch.append((x, target, src.lang))
        if len(batch) < a.batch:
            continue

        feats = M.features(processor, [b[0] for b in batch], device, dtype)
        lab = M.labels(processor, [b[1] for b in batch], [b[2] for b in batch]).to(device)
        audio_secs += sum(len(b[0]) for b in batch) / data.SR
        batch = []
        with amp():
            loss = model(input_features=feats, labels=lab).loss / a.accum
        scaler.scale(loss).backward()
        micro += 1
        if micro % a.accum:
            continue

        scaler.unscale_(opt)
        torch.nn.utils.clip_grad_norm_(params, 1.0)
        scaler.step(opt); scaler.update(); opt.zero_grad(set_to_none=True); sched.step()
        step += 1
        if step % 10 == 0:
            dt = time.time() - t_log
            log({"train/loss": loss.item() * a.accum, "train/lr": sched.get_last_lr()[0],
                 "train/audio_seconds_per_second": audio_secs / dt, "train/epoch": epoch,
                 "train/rows_without_target": missing})
            print(f"step {step} loss {loss.item() * a.accum:.4f} lr {sched.get_last_lr()[0]:.2e} "
                  f"{audio_secs / dt:.1f} s-audio/s{f' ({missing} rows had no restored target)' if missing else ''}",
                  flush=True)
            audio_secs, t_log = 0.0, time.time()

        metrics = run_eval() if step % a.eval_every == 0 else None
        if metrics or time.time() - last_save > a.save_minutes * 60:
            save("eval" if metrics else "timer", metrics)
            last_save = time.time()
        if step >= a.max_steps or stop["now"] or time.time() > deadline - 600:
            break

    if step >= a.max_steps:
        save("finished", run_eval())
    else:
        save("session limit — rerun to continue")
    if wb:
        wb.finish()
    os._exit(0)


if __name__ == "__main__":
    main()
