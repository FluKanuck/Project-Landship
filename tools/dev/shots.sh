#!/bin/bash
# Re-import changed assets, then run a director scenario under a virtual display.
#   tools/dev/shots.sh quick /tmp/shots [extra user args...]
cd "$(dirname "$0")/../.."
SCEN=${1:-quick}; OUT=${2:-/tmp/shots}; shift 2
rm -rf "$OUT"
timeout 300 godot --headless --path . --import >/dev/null 2>&1
timeout 900 xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 $GODOT_ARGS -- --scenario=$SCEN --out=$OUT "$@" 2>&1 \
  | grep -E "SCRIPT|ERROR|shot|director|   D1" | grep -vE "ALSA|status < 0|resources still in use|RIDs of type"
