#!/bin/zsh
# Records one clip of the real game with its real mixed audio and measures it (docs/audio-capture.md).
#
#   tools/capture_clip.sh OUTDIR NAME FRAMES [game flags after the --]
#   tools/capture_clip.sh /tmp/cap storm 2000 --town=1 --stage=night --slots=built --weather=storm --hour=21 --capture=walk --capture-route=storm
#
# Godot's movie writer renders the game frame by frame at 30 fps (so a slow machine does not change the sound) and writes the AVI (MJPEG + the Master's own PCM); the game's
# `--capture=` (tools/capture_tap.gd) writes the stems of each bus next to it. FRAMES is the length of the run: the first 5 seconds are the loading, the clip is what follows.
# OUTDIR/raw/NAME.avi, OUTDIR/raw/NAME/ (stems, meta.csv), OUTDIR/raw/NAME_x/audio.wav, OUTDIR/NAME.json and NAME.txt (the numbers). One Godot at a time.
set -e
OUT=$1; NAME=$2; FRAMES=$3; shift 3
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT/raw"
rm -rf "$OUT/raw/$NAME" "$OUT/raw/${NAME}_x"
"$GODOT" --path "$HERE" --write-movie "$OUT/raw/$NAME.avi" --fixed-fps 30 --quit-after "$FRAMES" -- \
  --shot="$OUT/raw/never.png" --frames=99999999 --winpx=1920x1080 --os-scale=1 --hide-lesson --no-banner "$@" --capture-out="$OUT/raw/$NAME" > "$OUT/raw/$NAME.log" 2>&1
grep -E "CAPTURE start|SCRIPT ERROR|recorded in" "$OUT/raw/$NAME.log" || true
python3 "$HERE/tools/avi_extract.py" "$OUT/raw/$NAME.avi" "$OUT/raw/${NAME}_x" --luma="$OUT/raw/${NAME}_luma.csv"
python3 "$HERE/tools/audio_capture.py" "$OUT/raw/$NAME" --wav "$OUT/raw/${NAME}_x/audio.wav" --luma "$OUT/raw/${NAME}_luma.csv" --name "$NAME" --json "$OUT/$NAME.json" | tee "$OUT/$NAME.txt"
