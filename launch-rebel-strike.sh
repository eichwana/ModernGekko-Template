#!/usr/bin/env bash
# launch-rebel-strike.sh — Rebel Strike via ModernGekko (interpreter mode)
# Location: ~/Games/GC/ModernGekko-Template/launch-rebel-strike.sh
#
# Usage:
#   ./launch-rebel-strike.sh                  # plain launch, logs to file
#   ./launch-rebel-strike.sh --hud            # MangoHud overlay
#   ./launch-rebel-strike.sh --scale          # gamescope 960x540 -> 1080p fullscreen
#   ./launch-rebel-strike.sh --scale 1440p    # gamescope 1280x720 -> 1440p fullscreen
#   extra args are forwarded to moderngekko-run, e.g.:
#   ./launch-rebel-strike.sh --graphics Vulkan

set -euo pipefail

PROJECT_DIR="$HOME/Games/GC/ModernGekko-Template"
LOG_FILE="$PROJECT_DIR/rebel-strike.log"
MAX_LOG_LINES=2000

USE_HUD=false
USE_SCALE=""
RUN_ARGS=()

# ---- parse our own flags, forward the rest to the runner -------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hud)   USE_HUD=true; shift ;;
    --scale) USE_SCALE="${2:-1080p}"; shift; shift ;;
    *)       RUN_ARGS+=("$1"); shift ;;
  esac
done

cd "$PROJECT_DIR"

# ---- trim old logs so they don't grow forever ------------------------------
[[ -f "$LOG_FILE" ]] && tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"

# ---- optional gamescope scaling --------------------------------------------
SCALE_CMD=()
if [[ -n "$USE_SCALE" ]]; then
  case "$USE_SCALE" in
    1080p) SCALE_CMD=(gamescope -W 1920 -H 1080 -w 960  -h 540  -f -r 60 --) ;;
    1440p) SCALE_CMD=(gamescope -W 2560 -H 1440 -w 1280 -h 720  -f -r 60 --) ;;
    2160p) SCALE_CMD=(gamescope -W 3840 -H 2160 -w 1920 -h 1080 -f -r 60 --) ;;
    ultra) SCALE_CMD=(gamescope -W 3440 -H 1440 -w 3440 -h 1440 -f -r 60 --) ;;
    *)     echo "Unknown scale '$USE_SCALE' (use 1080p|1440p|2160p), skipping." >&2 ;;
  esac
fi

# ---- optional MangoHud ------------------------------------------------------
HUD_CMD=()
$USE_HUD && command -v mangohud >/dev/null 2>&1 && HUD_CMD=(mangohud)

echo "[launcher] $(date)  mode: interpreter  args: ${RUN_ARGS[*]:-none} hud:$USE_HUD scale:${USE_SCALE:-off}" >> "$LOG_FILE"

# ---- go ---------------------------------------------------------------------
exec "${SCALE_CMD[@]}" "${HUD_CMD[@]}" \
  ./lib/ModernGekko/build/moderngekko-run \
    --game extracted/rebel-strike \
    --allow-interpreter \
    "${RUN_ARGS[@]}" \
    >> >(tee -a "$LOG_FILE")
