#!/bin/zsh
# THE HUD AUDIT PROBE (PH7): re-measures how much of the screen the UI covers, how much of the centre zone, and what hides the dead, on a set of staged scenes, and checks the
# CLUTTER BUDGET (tools/ui_audit/budget.json). About 5 to 8 minutes on a busy laptop for the default set (seven scenes at 1280x720 on town 1); one Godot at a time.
#
#   tools/ui_audit/run_audit.sh [OUTDIR] [--sizes 1280x720,1280x800,1920x1080,1024x640] [--scenes probe|all|a_arrive,b_opening,...] [--seeds each|1,3,5] [--skip-run]
#
# OUTDIR (default /tmp/ui_audit) gets OUTDIR/<size>/s<seed>/<snapshot>/{full,flags,nohud,world,e_<part>}.png, meta.json, result.json and sheet.png for each snapshot,
# OUTDIR/summary.md (the table), OUTDIR/budget.txt (the verdict). --skip-run measures the pictures already in OUTDIR. The exit status is 1 when a budget line fails.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=/tmp/ui_audit
if [[ $# -gt 0 && "$1" != --* ]]; then OUT=$1; shift; fi
SIZES=1280x720
SCENES=probe
SEEDS=1
SKIP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sizes) SIZES=$2; shift 2;;
    --scenes) SCENES=$2; shift 2;;
    --seeds) SEEDS=$2; shift 2;;
    --skip-run) SKIP=1; shift;;
    *) echo "unknown flag $1"; exit 2;;
  esac
done
mkdir -p "$OUT"
if [[ $SKIP == 0 ]]; then
  python3 "$HERE/run_scenes.py" "$OUT" --scenes "$SCENES" --sizes "$SIZES" --seeds "$SEEDS"
fi
python3 "$HERE/analyze.py" --all "$OUT" > "$OUT/analyze.txt"
python3 "$HERE/report.py" "$OUT" --budget > "$OUT/report.txt"
cat "$OUT/summary.md"
python3 "$HERE/check_budget.py" "$OUT" | tee "$OUT/budget.txt"
