"""Small local Parquet files with each source's real column layout, built from
~100 rows of AMI's validation split. The smoke test runs the whole pipeline on
these with whisper-tiny, in minutes, without touching the full datasets."""
import sys
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import data  # noqa: E402

out = Path(__file__).resolve().parent / "fixtures"
out.mkdir(exist_ok=True)
if (out / "done").exists():
    print("fixtures present")
    sys.exit(0)

src = data.Source("edinburghcstr/ami", "ihm", "validation", "text", "en", data.AMI_KEY)
rows = []
for r in data.stream(src):
    if len(str(r["text"]).split()) >= 1:
        rows.append(r)
    if len(rows) >= 120:
        break
audio = [{"bytes": r["audio"]["bytes"], "path": r["audio"].get("path")} for r in rows]


def write(name, cols):
    pq.write_table(pa.table(cols), out / f"{name}.parquet")


ami = {"meeting_id": [r["meeting_id"] for r in rows], "audio_id": [r["audio_id"] for r in rows],
       "text": [r["text"] for r in rows], "audio": audio,
       "begin_time": [r["begin_time"] for r in rows], "end_time": [r["end_time"] for r in rows],
       "microphone_id": [r["microphone_id"] for r in rows], "speaker_id": [r["speaker_id"] for r in rows]}
write("ami_ihm", ami)
# Same utterances, same keys, a different "microphone": exercises sdm reusing
# the targets restored from ihm.
write("ami_sdm", {**ami, "audio_id": [a.replace("_H0", "_SDM") for a in ami["audio_id"]],
                  "microphone_id": ["SDM1"] * len(rows)})
vox = {"audio_id": [f"vox{i}" for i in range(len(rows))], "audio": audio,
       "raw_text": [t.capitalize() for t in ami["text"]]}
write("vox_en", vox)
write("vox_fr", vox)
write("vox_french_accent", {**vox, "accent": ["en_fr" if i % 2 else "en_de" for i in range(len(rows))]})
write("ami_far_field", ami)
write("earnings22_calls", {"file_id": ["f"] * len(rows), "segment_id": [str(i) for i in range(len(rows))],
                           "audio": audio, "transcription": [t.capitalize() + "." for t in ami["text"]]})
(out / "done").write_text("ok")
print(f"wrote fixtures from {len(rows)} AMI rows")
import os; os._exit(0)  # noqa: E702 — streaming cleanup can hang shutdown
