"""Text side of training: scoring, and repairing the style of human transcripts.

Most free human transcripts are the right words in the wrong style. AMI and
EdAcc are ALL CAPS with no punctuation ("IF YOU IF YOU S. S. H."); VoxPopuli
is cased but unpunctuated. Training on them as-is teaches turbo to write that
way. `restore_style` keeps the human's words and borrows casing and
punctuation from what the base model itself produced for the same audio.

Run `python text.py` for the self-check.
"""
import difflib
import re

FILLERS = {"uh", "um", "er", "erm", "ah", "hmm", "mm", "mhm", "uh-huh", "huh"}
NUMBER_WORDS = set(
    "zero one two three four five six seven eight nine ten eleven twelve thirteen "
    "fourteen fifteen sixteen seventeen eighteen nineteen twenty thirty forty fifty "
    "sixty seventy eighty ninety hundred thousand million billion first second third".split())
END = ".?!"


def norm_word(w: str) -> str:
    return re.sub(r"[^a-z0-9']", "", w.lower()).strip("'")


def scoring_words(s: str) -> list[str]:
    """The normalizer every number in this project was scored with: case,
    punctuation, fillers and numbers (digits and words) ignored, so "10"
    against "ten" is not an error."""
    s = re.sub(r"[^a-z' ]", " ", s.lower().replace("-", " ").replace("%", " percent "))
    return [w.strip("'") for w in s.split()
            if w.strip("'") and w not in FILLERS and w not in NUMBER_WORDS]


def edit_distance(r: list[str], h: list[str]) -> int:
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)]


def wer(refs: list[str], hyps: list[str]) -> float:
    errs = words = 0
    for r, h in zip(refs, hyps):
        rw = scoring_words(r)
        errs += edit_distance(rw, scoring_words(h))
        words += len(rw)
    return errs / max(1, words)


def style_stats(hyps: list[str]) -> dict:
    """What WER cannot see: training on unpunctuated text makes the model
    stop punctuating, and the normalizer above strips punctuation before
    scoring. Tracked separately so that regression shows up."""
    long = [h.strip() for h in hyps if len(h.split()) >= 4]
    if not long:
        return {"punctuated": None, "cased": None}
    return {"punctuated": sum(h[-1] in END for h in long) / len(long),
            "cased": sum(any(c.isupper() for c in h) for h in long) / len(long)}


def _sentence_case(words: list[str]) -> list[str]:
    out, start = [], True
    for w in words:
        if w == "i" or w.startswith("i'"):
            w = "I" + w[1:]
        if start and w:
            w = w[0].upper() + w[1:]
        out.append(w)
        start = w[-1:] in END if w else start
    return out


def is_shouting(text: str) -> bool:
    letters = [c for c in text if c.isalpha()]
    return bool(letters) and sum(c.isupper() for c in letters) / len(letters) > 0.9


def restore_style(human: str, teacher: str | None) -> str:
    """Human words, teacher style.

    Where the two agree on a word, the teacher's spelling of it wins — its
    casing and the punctuation attached to it. Where they disagree, the
    human word wins, lower-cased if the human text was shouting. Words only
    the teacher heard are dropped: the human transcript is the ground truth.
    Fillers are dropped too; turbo does not write them and notes should not
    have them.

    `teacher` None means "too short to bother running the model": one or two
    words get sentence case and a full stop, which is what turbo writes.
    """
    shouting = is_shouting(human)
    hw = [w for w in human.split() if norm_word(w) not in FILLERS and norm_word(w)]
    if not hw:
        return ""
    if teacher is None:
        words = [w.lower() for w in hw] if shouting else hw
        out = " ".join(_sentence_case(words))
        return out if out[-1] in END else out + "."

    tw = teacher.split()
    hn = [norm_word(w) for w in hw]
    tn = [norm_word(w) for w in tw]
    out: list[str] = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(a=hn, b=tn, autojunk=False).get_opcodes():
        if op == "equal":
            out += tw[j1:j2]
        elif op in ("replace", "delete"):
            out += [w.lower() if shouting else w for w in hw[i1:i2]]
    if not out:
        return ""
    if shouting:
        # Shouted words that the teacher did not vouch for need casing from
        # somewhere: sentence starts and "I". Teacher-matched words keep theirs.
        out = _sentence_case(out)
    else:
        out[0] = out[0][0].upper() + out[0][1:]
    if out[-1][-1] not in END and tw and tw[-1][-1:] in END:
        out[-1] += tw[-1][-1]
    return " ".join(out)


def _selftest() -> None:
    fails = 0

    def check(what, got, want):
        nonlocal fails
        ok = got == want
        fails += not ok
        print(f"  {'ok  ' if ok else 'FAIL'} {what}" + ("" if ok else f"\n        got  {got!r}\n        want {want!r}"))

    print("restore_style:")
    check("shouted AMI, teacher agrees",
          restore_style("IT IS NOT SPECIFICALLY POINTED AT CHINA",
                        "It is not specifically pointed at China."),
          "It is not specifically pointed at China.")
    check("human word wins where they differ",
          restore_style("WE NEED THE PYRUVATE NOW", "We need the pirouette now."),
          "We need the pyruvate now.")
    check("teacher-only words are dropped",
          restore_style("THE MEETING IS OVER", "The meeting is over. Thank you."),
          "The meeting is over.")
    check("fillers go, teacher punctuation stays",
          restore_style("UM SO I THINK UH WE SHOULD", "So, I think we should."),
          "So, I think we should.")
    check("cased but unpunctuated VoxPopuli keeps its own case",
          restore_style("Nevertheless reaching a good deal in Copenhagen is our common interest",
                        "Nevertheless, reaching a good deal in Copenhagen is our common interest."),
          "Nevertheless, reaching a good deal in Copenhagen is our common interest.")
    check("short utterance without a teacher", restore_style("YEAH", None), "Yeah.")
    check("I is capitalised", restore_style("I'M NOT SURE", None), "I'm not sure.")
    check("only fillers", restore_style("UM UH", None), "")

    print("scoring:")
    check("case, punctuation and numbers ignored",
          wer(["We have 10 essays."], ["we have ten essays"]), 0.0)
    check("one substitution in four words", wer(["a b c d"], ["a b x d"]), 0.25)
    check("style stats", style_stats(["This is a sentence.", "this is not punctuated"]),
          {"punctuated": 0.5, "cased": 0.5})

    print("PASS" if not fails else f"FAIL: {fails} case(s)")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    _selftest()
