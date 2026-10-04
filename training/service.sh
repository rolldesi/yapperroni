#!/usr/bin/env bash
# Training as a launchd service on a dedicated Mac: starts at login, restarts
# if the process dies, checkpoints to the Hugging Face store every hour, live
# on W&B. Survives the lid closed only with `sudo pmset -a disablesleep 1`.
#
#   ./service.sh install    # write the LaunchAgent and start it
#   ./service.sh stop       # stop and remove it (saves first)
#   ./service.sh status
set -euo pipefail
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=com.yapperroni.training
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STORE="${STORE:-hf:rolldesi/yapperroni-train}"

case "${1:-}" in
install)
  mkdir -p "$HOME/Library/LaunchAgents" "$T/runs"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>WorkingDirectory</key><string>$T</string>
  <key>ProgramArguments</key><array>
    <string>$T/.venv/bin/python</string><string>train.py</string>
    <string>--store</string><string>$STORE</string>
    <string>--decoder-only</string><string>--batch</string><string>8</string><string>--accum</string><string>4</string>
    <string>--max-steps</string><string>${MAX_STEPS:-2000}</string>
    <string>--max-hours</string><string>100000</string>
    <string>--save-minutes</string><string>60</string>
    <string>--eval-every</string><string>250</string><string>--eval-n</string><string>200</string>
    <string>--wandb</string><string>yapperroni</string>
  </array>
  <key>EnvironmentVariables</key><dict>
    <key>YAPPERRONI_DTYPE</key><string>fp32</string>
    <key>PYTHONUNBUFFERED</key><string>1</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <!-- Restart only when it dies; a finished run (exit 0) stays finished. -->
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>60</integer>
  <!-- Time to finish the step and save before launchd escalates to SIGKILL. -->
  <key>ExitTimeOut</key><integer>300</integer>
  <key>StandardOutPath</key><string>$T/runs/train.log</string>
  <key>StandardErrorPath</key><string>$T/runs/train.log</string>
</dict></plist>
PL
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "installed and started $LABEL — log: $T/runs/train.log" ;;
stop)
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null && echo "stopped (it saved before exiting)" || echo "was not running"
  rm -f "$PLIST" ;;
status)
  launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -E "state =|pid =|last exit code" || echo "not installed" ;;
*) echo "usage: $0 install|stop|status"; exit 2 ;;
esac
