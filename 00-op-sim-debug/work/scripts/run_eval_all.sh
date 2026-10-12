#!/bin/bash
# Run scripts/run_eval.sh for several configurations on the evaluation events, several at a time.
# (scripts/run_fixes.sh does the same, choosing the fixes with options instead of configuration names.)
#
#   scripts/run_eval_all.sh <config> [<config> ...]
#   scripts/run_eval_all.sh loo          stock, none, all, and all-X for every fix id (the leave-one-out evaluation)
#
# Optional variables:
#   NJOBS=<n>          runs at the same time (default 6)
#   EVENTS="..."       default "mix:4 mix:0 mix:2 sol:0 sol:3 sol:5"
#
# Logs: $DATA_DIR/eval/logs/<config>_<sol|mix><i>.log

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR=$WORK_DIR/data                           # EDIT: absolute path of the directory where the data is saved

if ! mkdir -p "$DATA_DIR"; then                   # create it if it does not exist
  printf 'cannot create DATA_DIR=%s: edit DATA_DIR at the top of %s\n' "$DATA_DIR" "$0" >&2
  exit 2
fi
DATA=$DATA_DIR
EVENTS=${EVENTS:-"mix:4 mix:0 mix:2 sol:0 sol:3 sol:5"}

source $WORK_DIR/scripts/eval_switches.sh

CONFIGS="$*"
if [ "$CONFIGS" = loo ]; then
  CONFIGS="stock none all"
  for id in $ALL_IDS; do
    CONFIGS="$CONFIGS all-$id"
  done
fi

mkdir -p $DATA/eval/logs

for config in $CONFIGS; do
  for event in $EVENTS; do
    printf '%s %s %s\n' $config ${event%:*} ${event#*:}
  done
done \
| xargs -P ${NJOBS:-6} -L 1 bash -c '
    log='$DATA'/eval/logs/$0_$1$2.log
    '$WORK_DIR'/scripts/run_eval.sh $0 $1 $2 > $log 2>&1
    tail -1 $log'
