#!/usr/bin/env bash
# Train on this Mac. Decoder-only LoRA in bf16 — measured on an M5 at 2.6
# clips/s against 0.2 for the full model in fp32; the encoder (accents, rooms)
# is left for a cloud GPU. Everything lives in runs/local; rerun to resume.
#
#   nohup caffeinate -i ./local.sh >/dev/null 2>&1 &     # start, detached
#   tail -f runs/local/run.log                           # watch
#   pkill -f "train.py --store runs/local"               # stop (resumable)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
S=runs/local
mkdir -p "$S"
exec >> "$S/run.log" 2>&1
echo "=== $(date '+%F %T') local run starts"

# A third of AMI to begin with; raise AMI_ROWS and rerun to restore more.
.venv/bin/python prepare.py --store "$S" --sources ami_ihm \
    --max-rows "ami_ihm=${AMI_ROWS:-30000}" --max-hours 1000 --batch 16

.venv/bin/python train.py --store "$S" --decoder-only --batch 8 --accum 4 \
    --max-hours 1000 --save-minutes 30 --eval-every 500 --eval-n 200
echo "=== $(date '+%F %T') local run ends"
