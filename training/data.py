"""Public speech data, streamed — nothing is downloaded whole.

Every source is read from the Hugging Face Parquet mirror of the dataset,
which needs no loading script and no account. Audio is decoded here with
soundfile rather than by `datasets`, which keeps its own decoder dependency
(and its version churn) out of the picture.
"""
import io
from dataclasses import dataclass, field

import numpy as np
import soundfile as sf
from datasets import Audio, interleave_datasets, load_dataset

SR = 16_000
MAX_SECONDS = 30.0  # whisper's window; longer clips would be truncated


@dataclass
class Source:
    repo: str
    config: str
    split: str
    text: str
    lang: str
    # Restored targets are looked up by this key. AMI's close-talk and
    # far-field copies of an utterance share one, so the teacher runs once on
    # the clean headset audio and both copies train on the result.
    key: tuple[str, ...] = ("audio_id",)
    restore: bool = True
    where: dict = field(default_factory=dict)  # column -> required value

    def url(self) -> str:
        return f"hf://datasets/{self.repo}@refs%2Fconvert%2Fparquet/{self.config}/{self.split}/*.parquet"


AMI_KEY = ("meeting_id", "speaker_id", "begin_time", "end_time")

TRAIN = {
    "ami_ihm": Source("edinburghcstr/ami", "ihm", "train", "text", "en", AMI_KEY),
    "ami_sdm": Source("edinburghcstr/ami", "sdm", "train", "text", "en", AMI_KEY),
    "vox_en": Source("facebook/voxpopuli", "en", "train", "raw_text", "en"),
    # A little French so an English-only mix does not wear away the language
    # detection that made turbo usable on French lectures.
    "vox_fr": Source("facebook/voxpopuli", "fr", "train", "raw_text", "fr"),
}
# Which source's restored targets a source trains on.
TARGETS_FROM = {"ami_sdm": "ami_ihm"}
DEFAULT_MIX = {"ami_sdm": 0.35, "ami_ihm": 0.15, "vox_en": 0.40, "vox_fr": 0.10}

# Never trained on. Fixed before the first step so every checkpoint is
# scored on the same clips.
EVAL = {
    "vox_french_accent": Source("facebook/voxpopuli", "en_accented", "test", "raw_text", "en",
                                where={"accent": "en_fr"}, restore=False),
    "ami_far_field": Source("edinburghcstr/ami", "sdm", "test", "text", "en", AMI_KEY, restore=False),
    "earnings22_calls": Source("distil-whisper/earnings22", "chunked", "test", "transcription", "en",
                               ("file_id", "segment_id"), restore=False),
}


def key_of(row: dict, src: Source) -> str:
    return "|".join(str(row[k]) for k in src.key)


def decode(audio: dict) -> np.ndarray | None:
    x, sr = sf.read(io.BytesIO(audio["bytes"]), dtype="float32", always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        from scipy.signal import resample_poly
        g = np.gcd(sr, SR)
        x = resample_poly(x, SR // g, sr // g).astype(np.float32)
    if len(x) < SR * 0.3 or len(x) > SR * MAX_SECONDS:
        return None
    return x


def stream(src: Source, local_files: list[str] | None = None):
    """Rows with raw audio bytes. `local_files` swaps the remote Parquet for
    local ones — the smoke test runs on a few hundred rows this way."""
    ds = load_dataset("parquet", data_files=local_files or src.url(), split="train", streaming=True)
    ds = ds.cast_column("audio", Audio(decode=False))
    for col, val in src.where.items():
        ds = ds.filter(lambda r, c=col, v=val: r[c] == v)
    return ds


def mixed(mix: dict[str, float], seed: int, local: dict[str, list[str]] | None = None):
    """One stream drawing from each source in proportion. Every row carries
    its source name, so the batch knows which language prefix and which
    restored-target table it needs."""
    names = list(mix)
    parts = []
    for n in names:
        src = TRAIN[n]
        cols = ["audio", src.text, *src.key]
        ds = stream(src, (local or {}).get(n)).select_columns(cols)
        ds = ds.map(lambda r, n=n, s=src: {"source": n, "key": key_of(r, s), "human": r[s.text]},
                    remove_columns=[c for c in cols if c != "audio"])
        parts.append(ds.shuffle(seed=seed, buffer_size=500))
    total = sum(mix.values())
    return interleave_datasets(parts, probabilities=[mix[n] / total for n in names], seed=seed,
                               stopping_strategy="all_exhausted")


def eval_rows(name: str, n: int, local_files: list[str] | None = None) -> list[dict]:
    src = EVAL[name]
    out = []
    for r in stream(src, local_files):
        x = decode(r["audio"])
        if x is None or not str(r[src.text]).strip():
            continue
        out.append({"audio": x, "text": r[src.text], "lang": src.lang})
        if len(out) >= n:
            break
    return out
