"""Where checkpoints and restored transcripts live between sessions.

Option A hands one training run back and forth between Kaggle and Colab, so
nothing may live only on the machine that happens to be running: every
checkpoint and every batch of restored targets goes to the store, and every
session starts by pulling from it.

`--store runs/local` is a folder (the smoke test uses this). `--store
hf:you/yapperroni-train` is a private Hugging Face model repo; it needs
HF_TOKEN in the environment.
"""
import os
import shutil
from pathlib import Path


class Store:
    def __init__(self, spec: str, cache: str = ".cache/store"):
        self.hf = spec.startswith("hf:")
        self.cache = Path(cache)
        if self.hf:
            from huggingface_hub import HfApi
            self.repo = spec[3:]
            self.api = HfApi(token=os.environ.get("HF_TOKEN"))
            self.api.create_repo(self.repo, private=True, exist_ok=True)
            self.root = self.cache / self.repo.replace("/", "__")
        else:
            self.root = Path(spec)
        self.root.mkdir(parents=True, exist_ok=True)

    def path(self, sub: str) -> Path:
        return self.root / sub

    def push(self, sub: str) -> None:
        """Upload `sub` (a file or folder under the local root)."""
        if not self.hf:
            return
        p = self.path(sub)
        if p.is_dir():
            self.api.upload_folder(repo_id=self.repo, folder_path=str(p), path_in_repo=sub,
                                   commit_message=f"update {sub}", delete_patterns=["*"])
        else:
            self.api.upload_file(repo_id=self.repo, path_or_fileobj=str(p), path_in_repo=sub,
                                 commit_message=f"update {sub}")

    def pull(self, sub: str) -> bool:
        """Fetch `sub` from the remote. True when it exists locally afterwards."""
        if self.hf:
            from huggingface_hub import snapshot_download
            snapshot_download(self.repo, allow_patterns=[sub, f"{sub}/*"], local_dir=str(self.root),
                              token=os.environ.get("HF_TOKEN"))
        return self.path(sub).exists()

    def replace_dir(self, sub: str, staged: Path) -> None:
        """Swap a freshly written folder into place, then push it. Writing to
        a staging folder first means a crash mid-save never leaves a
        half-written checkpoint where resume will look for it."""
        dest = self.path(sub)
        if dest.exists():
            shutil.rmtree(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staged), str(dest))
        self.push(sub)
