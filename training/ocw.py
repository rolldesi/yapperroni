"""MIT OpenCourseWare lectures as training data: archive.org video, MIT's captions.

The first run trained on meetings and parliament and got worse on lectures
(three MIT lectures, 6 Oct: 8.6% → 11.9%). AMI's verbatim transcripts taught
it stutters and false starts, about twice turbo's inserted words, and
VoxPopuli's unpunctuated text cost sentence ends. OCW captions are made by
people, cased, punctuated and cleaned of false starts, which is the style
lecture notes want, spoken by the kind of speaker the app records.

Each lecture becomes one parquet of ≤30 s windows cut on caption-cue
boundaries. Every second window also gets a muffled copy (band-limited, room
reflections, pink noise), the condition the last model lost most on. Audio
streams from archive.org through ffmpeg and only the windows are kept, as
Opus (about 11 MB an hour). Finished lectures are skipped, so a rerun
resumes.

The benchmark courses (14.73, 7.016, 18.06) and their lecturers are never
ingested. The eval courses share no lecturer with the training courses.

    python ocw.py --out data/ocw
"""
import argparse
import io
import re
import shutil
import subprocess
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq
import soundfile as sf
from scipy.signal import butter, sosfilt

SR = 16_000
OCW = "https://ocw.mit.edu"
# Lecturers with accents where possible (Tsitsiklis, Devadas), and the
# subjects the benchmark covers (biology, maths, economics) without its courses.
TRAIN = [
    "6-006-introduction-to-algorithms-fall-2011",
    "7-012-introduction-to-biology-fall-2004",
    "18-03-differential-equations-spring-2010",
    "6-041-probabilistic-systems-analysis-and-applied-probability-fall-2010",
    "5-111-principles-of-chemical-science-fall-2008",
    "6-034-artificial-intelligence-fall-2010",
    "15-401-finance-theory-i-fall-2008",
    "8-04-quantum-physics-i-spring-2013",
    "14-01-principles-of-microeconomics-fall-2023",
    "7-01sc-fundamentals-of-biology-fall-2011",
]
# Picks the best checkpoint. Rigollet teaches in English with a French accent;
# 18.S096 is a rotation of lecturers, several of them non-native speakers.
EVAL = ["18-650-statistics-for-applications-fall-2016",
        "18-s096-topics-in-mathematics-with-applications-in-finance-fall-2013"]
# Captions of speech that is not the lecturer's, or that the captioner could
# not hear: the target would hold words the audio barely does.
SKIP = re.compile(r"INAUDIBLE|UNINTELLIGIBLE|CROSSTALK|AUDIENCE:|STUDENT:|\[MUSIC")
SCHEMA = pa.schema([("audio", pa.struct([("bytes", pa.binary()), ("path", pa.string())])),
                    ("text", pa.string()), ("lecture", pa.string()), ("start", pa.float64())])


def get(url: str) -> str:
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def lectures(course: str) -> list[tuple[str, str, str]]:
    """(name, video url, caption url) for each lecture video, in course order."""
    page = get(f"{OCW}/courses/{course}/video_galleries/lecture-videos/")
    out = []
    for res in dict.fromkeys(re.findall(rf'href="(/courses/{course}/resources/[^"]+)"', page)):
        html = get(OCW + res)
        mp4 = re.search(r'https?://(?:www\.)?archive\.org/download/[^"\s]+\.mp4', html)
        vtt = re.search(rf'/courses/{course}/[0-9a-f]+_[^"/\s]+\.vtt', html)
        if mp4 and vtt:
            name = course.split("-")[0] + "." + course.split("-")[1] + "-" + res.rstrip("/").split("/")[-1]
            out.append((name, re.sub(r"^https?://(www\.)?", "https://", mp4.group(0)), OCW + vtt.group(0)))
    return out


def cues(vtt: str) -> list[tuple[float, float, str]]:
    def ts(t):
        h, m, s = t.split(":")
        return int(h) * 3600 + int(m) * 60 + float(s)
    out = []
    for block in vtt.split("\n\n"):
        lines = [l for l in block.strip().split("\n") if l]
        for i, l in enumerate(lines):
            m = re.match(r"(\S+) --> (\S+)", l)
            if m:
                out.append((ts(m.group(1)), ts(m.group(2)), " ".join(lines[i + 1:])))
                break
    return out


def clean(t: str) -> str:
    t = re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", t)       # [LAUGHTER], (inaudible)
    t = re.sub(r"\b[A-Z][A-Z .'-]+:\s*", " ", t)      # PROFESSOR:
    return " ".join(t.replace(">>", " ").split())


def windows(cs, max_s=28.0, gap_s=2.0):
    """Consecutive cues up to max_s long; a pause longer than gap_s starts a new window."""
    out, cur = [], []
    for c in cs:
        if cur and (c[1] - cur[0][0] > max_s or c[0] - cur[-1][1] > gap_s):
            out.append(cur)
            cur = []
        cur.append(c)
    return out + ([cur] if cur else [])


def ffmpeg() -> str:
    found = shutil.which("ffmpeg")
    if found:
        return found
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def load_audio(url: str, span: tuple[float, float] | None = None) -> np.ndarray:
    """Mono 16 kHz; with `span`, only that stretch, so an eval lecture
    fetches ten minutes of video instead of eighty."""
    cut = ["-ss", str(span[0]), "-t", str(span[1] - span[0])] if span else []
    # rw_timeout: a connection that went quiet while the Mac slept hung
    # ffmpeg for 37 minutes with the lid closed; now it fails and retries.
    net = ["-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "30",
           "-rw_timeout", "60000000"] if url.startswith("http") else []
    p = subprocess.run([ffmpeg(), "-nostdin", "-loglevel", "error", *net, *cut[:2], "-i", url, *cut[2:],
                        "-vn", "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"], capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode()[-300:])
    return np.frombuffer(p.stdout, np.int16).astype(np.float32) / 32768


def muffle(x: np.ndarray, rng: np.random.Generator, snr_db: float, top_hz: float) -> np.ndarray:
    """A laptop at the back of the hall, as the benchmark builds it in ffmpeg
    (band-pass, three reflections, pink noise). Training draws the cutoff and
    the noise level so the model does not learn one exact filter."""
    y = sosfilt(butter(4, [150, top_hz], btype="band", fs=SR, output="sos"), x)
    wet = 0.8 * y
    for ms, g in ((30, 0.35), (65, 0.25), (110, 0.15)):
        d = SR * ms // 1000
        wet[d:] += g * y[:-d]
    f = np.fft.rfftfreq(len(x), 1 / SR)
    pink = np.fft.irfft(np.fft.rfft(rng.standard_normal(len(x))) / np.sqrt(np.maximum(f, 20)), len(x))
    rms = lambda v: np.sqrt(np.mean(v ** 2)) + 1e-9  # noqa: E731
    out = wet + pink * rms(wet) / rms(pink) * 10 ** (-snr_db / 20)
    return (out / max(1.0, np.abs(out).max())).astype(np.float32)


def opus(x: np.ndarray) -> bytes:
    b = io.BytesIO()
    sf.write(b, x, SR, format="OGG", subtype="OPUS")
    return b.getvalue()


def ingest(name: str, video: str, vtt: str, out: Path, span: tuple[float, float] | None = None,
           train: bool = True) -> tuple[int, float]:
    """One lecture to out/clean/<name>.parquet and out/muffled/<name>.parquet.
    `video` is a URL or a local file. Returns (windows, hours)."""
    clean_p, muf_p = out / "clean" / f"{name}.parquet", out / "muffled" / f"{name}.parquet"
    if clean_p.exists():
        return -1, 0.0
    cs = cues(vtt)
    if span:
        cs = [c for c in cs if c[0] >= span[0] and c[1] <= span[1]]
    # A second of margin either side for the window padding.
    off = max(0.0, span[0] - 1) if span else 0.0
    x = load_audio(video, (off, span[1] + 1) if span else None)
    # ffmpeg can end early on a dropped connection and still exit 0: the
    # first test run wrote an eval lecture with no windows that way. Short
    # audio is a failed attempt, not a lecture.
    if not cs or len(x) / SR < cs[-1][1] - off - 5:
        raise RuntimeError(f"audio {len(x) / SR:.0f} s, captions run to {cs[-1][1] - off if cs else 0:.0f} s")
    rows, muf, secs = [], [], 0.0
    for k, w in enumerate(windows(cs)):
        a, b = max(0.0, w[0][0] - 0.2), w[-1][1] + 0.3
        text = clean(" ".join(c[2] for c in w))
        if b - a > 29.5 or b - a < 1.0 or not text or any(SKIP.search(c[2]) for c in w):
            continue
        seg = x[max(0, int((a - off) * SR)):int((b - off) * SR)]
        if len(seg) < SR:
            continue  # captions run past the end of the audio
        row = {"text": text, "lecture": name, "start": round(a, 2)}
        secs += len(seg) / SR
        rows.append({**row, "audio": {"bytes": opus(seg), "path": None}})
        if not train or k % 2 == 0:
            rng = np.random.default_rng(zlib.crc32(f"{name}|{a}".encode()))
            m = muffle(seg, rng, 10.0, 2800.0) if not train else \
                muffle(seg, rng, rng.uniform(5, 15), rng.uniform(2200, 4000))
            muf.append({**row, "audio": {"bytes": opus(m), "path": None}})
    if not rows:
        raise RuntimeError("no usable windows")
    for p, rs in ((muf_p, muf), (clean_p, rows)):  # clean last: it marks the lecture done
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(".tmp")
        pq.write_table(pa.Table.from_pylist(rs, schema=SCHEMA), tmp)
        tmp.rename(p)
    return len(rows), secs / 3600


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/ocw")
    ap.add_argument("--per-course", type=int, default=16, help="lectures per training course")
    ap.add_argument("--eval-lectures", type=int, default=4, help="lectures per eval course")
    ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    out = Path(a.out)

    jobs = []
    for course in EVAL:
        for name, video, vtt in lectures(course)[:a.eval_lectures]:
            # Ten minutes from a minute in, like the benchmark clips: past the
            # licence notice, and the same length from every lecture.
            jobs.append((name, video, vtt, out / "eval", (60.0, 660.0), False))
    for course in TRAIN:
        for name, video, vtt in lectures(course)[:a.per_course]:
            jobs.append((name, video, vtt, out / "train", None, True))
    print(f"{len(jobs)} lectures", flush=True)

    def run(j):
        name, video, vtt_url, dest, span, train = j
        for attempt in range(3):
            try:
                n, h = ingest(name, video, get(vtt_url), dest, span, train)
                print(f"{name}: " + ("already done" if n < 0 else f"{n} windows, {h:.2f} h"), flush=True)
                return
            except Exception as e:  # noqa: BLE001 — one bad lecture must not stop the rest
                print(f"{name}: attempt {attempt + 1} failed: {e!r}"[:300], flush=True)
        print(f"{name}: skipped", flush=True)

    with ThreadPoolExecutor(a.jobs) as pool:
        list(pool.map(run, jobs))
    for split in ("train", "eval"):
        for kind in ("clean", "muffled"):
            files = list((out / split / kind).glob("*.parquet"))
            rows = sum(pq.ParquetFile(f).metadata.num_rows for f in files)
            print(f"{split}/{kind}: {len(files)} lectures, {rows} windows", flush=True)


if __name__ == "__main__":
    main()
