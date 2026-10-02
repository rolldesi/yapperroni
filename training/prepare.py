"""One pass of base turbo over the training data, to repair transcript style.

For each source it streams the audio, runs the base model, and writes
`targets/<source>/part-NNNNN.parquet` rows of (key, text): the human words in
turbo's casing and punctuation (see text.restore_style). Progress is saved
to the store every `--flush` rows with the stream position, so the pass can
stop on one platform and continue on another without redoing work.

    python prepare.py --store hf:you/yapperroni-train
"""
import argparse
import json
import os
import signal
import time

import pyarrow as pa
import pyarrow.parquet as pq

import data
import model as M
import text
from store import Store


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", required=True)
    ap.add_argument("--sources", default="ami_ihm", help="sources whose text needs restoring")
    ap.add_argument("--model", default=M.BASE)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--flush", type=int, default=2000, help="rows per saved part")
    ap.add_argument("--max-rows", default="", help="per-source caps, e.g. ami_ihm=50000")
    ap.add_argument("--max-hours", type=float, default=11.5)
    ap.add_argument("--device", default="auto")
    ap.add_argument("--local", default="", help="source=file.parquet,... (smoke test)")
    a = ap.parse_args()

    store = Store(a.store)
    caps = {k: int(v) for k, v in (p.split("=") for p in a.max_rows.split(",") if p)}
    local = {k: [v] for k, v in (p.split("=") for p in a.local.split(",") if p)}
    device, dtype = M.device_and_dtype(a.device)
    processor, model = M.load(a.model, device, dtype)
    deadline = time.time() + a.max_hours * 3600
    stop = {"now": False}
    signal.signal(signal.SIGTERM, lambda *_: stop.update(now=True))

    for name in a.sources.split(","):
        src = data.TRAIN[name]
        sub = f"targets/{name}"
        store.pull(sub)
        state_file = store.path(f"{sub}/state.json")
        state = json.loads(state_file.read_text()) if state_file.exists() else {"rows": 0, "part": 0, "done": False}
        if state["done"]:
            print(f"{name}: already complete ({state['rows']} rows)")
            continue
        ds = data.stream(src, local.get(name))
        if "stream" in state:
            ds.load_state_dict(state["stream"])
        print(f"{name}: resuming at {state['rows']} rows" if state["rows"] else f"{name}: starting")

        rows, queue, t0, seen_keys = [], [], time.time(), set()

        def run_queue():
            if not queue:
                return
            hyps = M.transcribe(model, processor, [q[2] for q in queue], src.lang, device, dtype, a.batch)
            for (k, human, _), hyp in zip(queue, hyps):
                rows.append({"key": k, "text": text.restore_style(human, hyp)})
            queue.clear()

        def flush(final=False):
            run_queue()
            if rows:
                p = store.path(f"{sub}/part-{state['part']:05d}.parquet")
                p.parent.mkdir(parents=True, exist_ok=True)
                pq.write_table(pa.Table.from_pylist(rows), p)
                state["part"] += 1
                state["rows"] += len(rows)
                rows.clear()
            state["stream"] = ds.state_dict()
            state["done"] = final
            state_file.parent.mkdir(parents=True, exist_ok=True)
            state_file.write_text(json.dumps(state))
            store.push(sub)
            rate = state["rows"] / max(1e-6, time.time() - t0)
            print(f"{name}: {state['rows']} rows saved ({rate:.1f} rows/s this session)", flush=True)

        exhausted = True
        for r in ds:
            human = str(r[src.text] or "").strip()
            k = data.key_of(r, src)
            if not human or k in seen_keys:
                continue
            seen_keys.add(k)
            x = data.decode(r["audio"])
            if x is None:
                continue
            content = [w for w in human.split() if text.norm_word(w) not in text.FILLERS]
            if len(content) <= 2:
                rows.append({"key": k, "text": text.restore_style(human, None)})
            else:
                queue.append((k, human, x))
                if len(queue) >= a.batch:
                    run_queue()
            if len(rows) >= a.flush:
                flush()
            if state["rows"] + len(rows) + len(queue) >= caps.get(name, 10**12):
                break
            if stop["now"] or time.time() > deadline:
                exhausted = False
                break
        flush(final=exhausted)
        if not exhausted:
            print("stopping: time limit or SIGTERM — rerun to continue")
            break
    # The streaming readers' cleanup can hang interpreter shutdown.
    os._exit(0)


if __name__ == "__main__":
    main()
