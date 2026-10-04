"""Public speech data, streamed — nothing is downloaded whole.

Every source is read from the Hugging Face Parquet mirror of the dataset,
which needs no loading script and no account, with pyarrow over HTTP range
requests, 64 rows at a time.

Not through the `datasets` library: on real VoxPopuli its interleave read
ahead to infer column types and kept what it downloaded, growing at the
download rate — 37 GB of footprint in ten minutes on a 16 GB Mac, killed by
macOS before the first training step, three times. Here memory is one small
batch per source, and the resume position is exact (pass, file, row group,
row) rather than a shuffle buffer refilled on resume.
"""
import io
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field

import numpy as np
import pyarrow.parquet as pq
import soundfile as sf

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

    def files(self) -> list[str]:
        from huggingface_hub import HfApi
        tree = HfApi().list_repo_tree(self.repo, path_in_repo=f"{self.config}/{self.split}",
                                      repo_type="dataset", revision="refs/convert/parquet")
        return sorted(f"https://huggingface.co/datasets/{self.repo}/resolve/refs%2Fconvert%2Fparquet/{f.path}"
                      for f in tree if f.path.endswith(".parquet"))


AMI_KEY = ("meeting_id", "speaker_id", "begin_time", "end_time")

TRAIN = {
    "ami_ihm": Source("edinburghcstr/ami", "ihm", "train", "text", "en", AMI_KEY),
    "ami_sdm": Source("edinburghcstr/ami", "sdm", "train", "text", "en", AMI_KEY),
    # VoxPopuli's training text is already cased and punctuated (98% of
    # English rows, 88% of French — the rest start mid-sentence); only its
    # accented test split is not. So it trains on its own text, and the
    # teacher pass is AMI's alone.
    "vox_en": Source("facebook/voxpopuli", "en", "train", "raw_text", "en", restore=False),
    # A little French so an English-only mix does not wear away the language
    # detection that made turbo usable on French lectures.
    "vox_fr": Source("facebook/voxpopuli", "fr", "train", "raw_text", "fr", restore=False),
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


class _HTTPFile(io.RawIOBase):
    """Seekable read-only file over HTTP Range requests, so pyarrow can read
    just the row groups it needs. A small block cache, and retries: long runs
    meet read timeouts (one is how the first local run's log ended)."""
    BLOCK = 4 << 20

    def __init__(self, url: str, blocks: int = 8):
        self.url, self.pos, self.cache, self.max = url, 0, {}, blocks
        with self._open(urllib.request.Request(url, method="HEAD")) as r:
            self.size = int(r.headers["Content-Length"])

    @staticmethod
    def _open(req):
        for attempt in range(6):
            try:
                return urllib.request.urlopen(req, timeout=60)
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                if attempt == 5:
                    raise
                time.sleep(2 ** attempt)
                print(f"retrying after {e!r}", flush=True)

    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else self.pos + off if whence == 1 else self.size + off
        return self.pos

    def _block(self, i):
        if i not in self.cache:
            a = i * self.BLOCK
            b = min(self.size, a + self.BLOCK) - 1
            with self._open(urllib.request.Request(self.url, headers={"Range": f"bytes={a}-{b}"})) as r:
                self.cache[i] = r.read()
            if len(self.cache) > self.max:
                self.cache.pop(next(iter(self.cache)))
        return self.cache[i]

    def read(self, n=-1):
        n = self.size - self.pos if n < 0 else max(0, min(n, self.size - self.pos))
        out = bytearray()
        while n > 0:
            i, o = divmod(self.pos, self.BLOCK)
            chunk = self._block(i)[o:o + n]
            out += chunk
            self.pos += len(chunk)
            n -= len(chunk)
        return bytes(out)

    def readinto(self, b):
        d = self.read(len(b))
        b[:len(d)] = d
        return len(d)


def _open_parquet(path: str) -> pq.ParquetFile:
    if path.startswith("http"):
        # buffer_size streams each column chunk in pieces instead of reading
        # a whole 650 MB row group of audio into memory at once.
        return pq.ParquetFile(_HTTPFile(path), buffer_size=4 << 20, pre_buffer=False)
    return pq.ParquetFile(path)


class ParquetStream:
    """One source, row group by row group, 64 rows at a time.

    Shuffled by file, by row group within a file, and by row within each
    batch — every order derived from (seed, pass, position), so the state is
    four integers and a resume replays exactly the same sequence. With
    `cycle` it starts a new, differently shuffled pass when it runs out."""
    BATCH = 64

    def __init__(self, src: Source, local_files=None, seed: int = 0, shuffle: bool = True, cycle: bool = False):
        self.src, self.seed, self.shuffle, self.cycle = src, seed, shuffle, cycle
        self.paths = list(local_files) if local_files else src.files()
        self.columns = list(dict.fromkeys(["audio", src.text, *src.key, *src.where]))
        self.state = {"pass": 0, "file": 0, "group": 0, "row": 0}

    def state_dict(self) -> dict:
        return dict(self.state)

    def load_state_dict(self, state: dict) -> None:
        self.state = {k: int(state[k]) for k in ("pass", "file", "group", "row")}

    def _order(self, n: int, *salt: int) -> np.ndarray:
        if not self.shuffle:
            return np.arange(n)
        return np.random.default_rng([self.seed, self.state["pass"], *salt]).permutation(n)

    def __iter__(self):
        st = self.state
        while True:
            files = self._order(len(self.paths))
            while st["file"] < len(files):
                pf = _open_parquet(self.paths[files[st["file"]]])
                groups = self._order(pf.num_row_groups, st["file"] + 1)
                while st["group"] < len(groups):
                    g = int(groups[st["group"]])
                    seen = 0
                    for b, batch in enumerate(pf.iter_batches(batch_size=self.BATCH, row_groups=[g],
                                                              columns=self.columns)):
                        rows = batch.to_pylist()
                        for i in self._order(len(rows), st["file"] + 1, g + 1, b + 1):
                            seen += 1
                            if seen <= st["row"]:
                                continue  # resuming: already handed out before the stop
                            st["row"] = seen
                            row = rows[i]
                            if all(row[c] == v for c, v in self.src.where.items()):
                                yield row
                    st["group"] += 1
                    st["row"] = 0
                st["file"] += 1
                st["group"] = 0
            if not self.cycle:
                return
            self.state = st = {"pass": st["pass"] + 1, "file": 0, "group": 0, "row": 0}


def stream(src: Source, local_files: list[str] | None = None) -> ParquetStream:
    """One pass, in file order — for the restore pass and the eval sets."""
    return ParquetStream(src, local_files, shuffle=False)


class Mixer:
    """Draws from each source in proportion, forever. Which source each draw
    takes is a function of (seed, draw number), so resume needs only the
    draw count and each source's position. `epoch` is the number of complete
    passes the slowest source has made."""

    def __init__(self, mix: dict[str, float], seed: int, local: dict[str, list[str]] | None = None):
        self.names = list(mix)
        total = sum(mix.values())
        self.p = np.array([mix[n] / total for n in self.names])
        self.seed = seed
        self.draws = 0
        self.streams = {n: ParquetStream(TRAIN[n], (local or {}).get(n), seed=seed + k + 1, cycle=True)
                        for k, n in enumerate(self.names)}

    @property
    def epoch(self) -> int:
        return min(s.state["pass"] for s in self.streams.values())

    def state_dict(self) -> dict:
        return {"draws": self.draws, "streams": {n: s.state_dict() for n, s in self.streams.items()}}

    def load_state_dict(self, state: dict) -> None:
        self.draws = int(state["draws"])
        for n, s in state["streams"].items():
            if n in self.streams:
                self.streams[n].load_state_dict(s)

    def __iter__(self):
        its = {n: iter(s) for n, s in self.streams.items()}
        while True:
            n = self.names[np.random.default_rng([self.seed, self.draws]).choice(len(self.names), p=self.p)]
            self.draws += 1
            src = TRAIN[n]
            r = next(its[n])
            yield {"source": n, "key": key_of(r, src), "human": r[src.text], "audio": r["audio"]}


def mixed(mix: dict[str, float], seed: int, local: dict[str, list[str]] | None = None) -> Mixer:
    return Mixer(mix, seed, local)


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
