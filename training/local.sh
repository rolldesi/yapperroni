#!/usr/bin/env bash
# Train on this Mac. Decoder-only LoRA in bf16 — measured on an M5 at 2.6
# clips/s against 0.2 for the full model in fp32; the encoder (accents, rooms)
# is left for a cloud GPU. Everything lives in runs/local; rerun to resume.
#
#   nohup caffeinate -i ./local.sh >/dev/null 2>&1 &     # start, detached
#   tail -f runs/local/run.log                           # watch
#   pkill -TERM -f "bash ./local.sh"                     # pause: saves, then exits
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
S=runs/local
mkdir -p "$S"
exec >> "$S/run.log" 2>&1
echo "=== $(date '+%F %T') local run starts"

# A stop has to reach the step that is running and end the script, not
# just the step: a bare SIGTERM to prepare.py let the script go on and
# start training. Steps run in the background so the trap fires at once.
child=""
stop() { echo "=== $(date '+%F %T') paused"; [ -n "$child" ] && kill -TERM "$child" 2>/dev/null; wait "$child" 2>/dev/null; exit 0; }
trap stop TERM INT
step() { "$@" & child=$!; wait "$child"; child=""; }

# A third of AMI to begin with; raise AMI_ROWS and rerun to restore more.
step .venv/bin/python prepare.py --store "$S" --sources ami_ihm \
    --max-rows "ami_ihm=${AMI_ROWS:-30000}" --max-hours 1000 --batch 16

step .venv/bin/python train.py --store "$S" --decoder-only --batch 8 --accum 4 \
    --max-hours 1000 --save-minutes 30 --eval-every 500 --eval-n 200
echo "=== $(date '+%F %T') local run ends"
