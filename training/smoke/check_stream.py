"""Resume must replay the exact same rows: stop a stream mid-way, rebuild it
from its saved state, and compare what comes next — for one source and for
the mixer across sources and pass boundaries."""
import itertools
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import data  # noqa: E402

F = Path(__file__).resolve().parent / "fixtures"
local = {n: [str(F / f"{n}.parquet")] for n in ["ami_ihm", "ami_sdm", "vox_en", "vox_fr"]}
fails = 0


def check(what, ok):
    global fails
    fails += not ok
    print(f"  {'ok  ' if ok else 'FAIL'} {what}")


s = data.ParquetStream(data.TRAIN["ami_ihm"], local["ami_ihm"], seed=3, cycle=True)
it = iter(s)
[next(it) for _ in range(150)]                      # past one 120-row pass
saved = s.state_dict()
after = [data.key_of(r, data.TRAIN["ami_ihm"]) for r in itertools.islice(it, 20)]
s2 = data.ParquetStream(data.TRAIN["ami_ihm"], local["ami_ihm"], seed=3, cycle=True)
s2.load_state_dict(saved)
check("one source resumes on the same rows, past a pass boundary",
      after == [data.key_of(r, data.TRAIN["ami_ihm"]) for r in itertools.islice(iter(s2), 20)])
check("the pass counter moved", saved["pass"] == 1)

m = data.mixed({"ami_ihm": 1, "vox_en": 1, "vox_fr": 0.5}, 7, local)
it = iter(m)
[next(it) for _ in range(400)]
saved = m.state_dict()
after = [(r["source"], r["key"]) for r in itertools.islice(it, 30)]
m2 = data.mixed({"ami_ihm": 1, "vox_en": 1, "vox_fr": 0.5}, 7, local)
m2.load_state_dict(saved)
check("the mixer resumes on the same sources and rows",
      after == [(r["source"], r["key"]) for r in itertools.islice(iter(m2), 30)])

print("PASS" if not fails else f"FAIL: {fails}")
sys.exit(1 if fails else 0)
