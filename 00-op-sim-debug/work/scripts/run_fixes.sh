#!/bin/bash
# Run the light simulation of some events with the bug fixes you choose: all at once, or one by one.
#
#   scripts/run_fixes.sh [options] <event> [<event> ...]
#
# <event>    sol:<i> (solar neutrino only) or mix:<i> (neutrino + radiological background), e.g. sol:0 mix:4,
#            or  eval6  for the six evaluation events  mix:4 mix:0 mix:2 sol:0 sol:3 sol:5
#
# WHICH FIXES ARE ON
#   Each bug has a boolean FIX_<ID> (true = fixed, false = bug) in its own section of scripts/eval_switches.sh, with
#   its patch, stage and fcl parameter.  Without options, the values written there are used (all true).
#   The options below change them, in the order given:
#     --all-on                 every fix on
#     --all-off                every fix off (the patched build then reproduces the stock simulation)
#     --only B,C               only these fixes on
#     --all-except A,F         every fix on except these
#     --on X,Y   --off X,Y     turn some fixes on or off on top of the above
#   or for one command:  FIX_A=false scripts/run_fixes.sh sol:0
#   Bug ids:  N4 N71 N72 (G4 light) | B C D E N1 N2 N3 N6 (detsim) | F N5 A (reco).  N71 = N7.1, N72 = N7.2.
#
# WHAT TO RUN
#     (default)                one run, with the fixes as chosen
#     --one-by-one             one run with every fix off ("none"), then for every chosen fix one run with only
#                              that fix on ("none+X"): the effect of fixing each bug alone
#     --leave-one-out          one run with the chosen fixes, then for every chosen fix one run without it
#                              (with all fixes chosen: "all" and "all-X"): the effect of each bug in an otherwise
#                              fixed simulation.  This is what docs/SUMMARY.md and the notebook show.
#     --stock                  also run the official (unpatched CVMFS) code, as the reference
#     --dry-run                print the table of fixes ON/OFF, the fcl lines and the directories; run nothing
#     --jobs <n>               how many runs at the same time (default 2)
#     --host wcgpu1|dunegpvm   the machine (default: guessed from the machine name; see env/in-sl7.sh)
#
# EXAMPLES
#   scripts/run_fixes.sh --dry-run sol:0                     what "all fixes" means, without running
#   scripts/run_fixes.sh sol:0                               all fixes on, one event
#   scripts/run_fixes.sh --all-except A sol:0 mix:4          all fixes but A: the effect of bug A
#   scripts/run_fixes.sh --only B,C,D --one-by-one mix:4     none, none+B, none+C, none+D
#   scripts/run_fixes.sh --leave-one-out --stock eval6       the full evaluation (heavy: ~100 runs)
#
# Requirements: the patched build (scripts/build_eval.sh, once) and the input events in $DATA_DIR/events/ (from
# scripts/run_chain.sh; with KEEP_INTERMEDIATE=1 if a G4 fix N4, N71 or N72 is on).
#
# Results: $DATA_DIR/eval/run/<config>/<sol|mix>/evt<i>/  (light.npz, eval.npz, reco.root, stages_<config>.txt, which
# lists the fixes that were on).  <config> is the name of the set of fixes: all, none, all-A, none+B+C, ...
# Logs: $DATA_DIR/eval/logs/<config>_<sol|mix><i>.log.  A stage already run with the same fixes is not run again.

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR=$WORK_DIR/data                           # EDIT: absolute path of the directory where the data is saved
DATA=$DATA_DIR
EVAL_EVENTS="mix:4 mix:0 mix:2 sol:0 sol:3 sol:5"

source $WORK_DIR/scripts/eval_switches.sh

usage() {
  sed -n '2,/^$/p' "$0"
  exit 2
}

set_fixes_from_list() {            # set_fixes_from_list <true|false> B,C,...
  local id
  for id in ${2//,/ }; do
    if ! grep -qw -- "$id" <<< "$ALL_IDS"; then
      printf 'unknown fix id "%s"; the ids are: %s\n' "$id" "$ALL_IDS" >&2
      exit 2
    fi
    printf -v FIX_$id '%s' "$1"
  done
}


# ----------------------------------------------------------------------------------------------------------------------
# Options
# ----------------------------------------------------------------------------------------------------------------------

MODE=single
RUN_STOCK=no
DRY_RUN=0
NJOBS=2
EVENTS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --all-on)          set_all_fixes true ;;
    --all-off)         set_all_fixes false ;;
    --only)            set_all_fixes false;  set_fixes_from_list true  "$2"; shift ;;
    --all-except)      set_all_fixes true;   set_fixes_from_list false "$2"; shift ;;
    --on)              set_fixes_from_list true  "$2"; shift ;;
    --off)             set_fixes_from_list false "$2"; shift ;;
    --one-by-one)      MODE=one-by-one ;;
    --leave-one-out)   MODE=leave-one-out ;;
    --stock)           RUN_STOCK=yes ;;
    --dry-run)         DRY_RUN=1 ;;
    --jobs)            NJOBS=$2; shift ;;
    --host)            export SL7_HOST=$2; shift ;;
    eval6)             EVENTS="$EVENTS $EVAL_EVENTS" ;;
    sol:*|mix:*)       EVENTS="$EVENTS $1" ;;
    -h|--help)         usage ;;
    *)                 printf 'unknown argument "%s"\n\n' "$1" >&2; usage ;;
  esac
  shift
done

[ -n "$EVENTS" ] || usage
if ! mkdir -p "$DATA_DIR"; then                   # create it if it does not exist
  printf 'cannot create DATA_DIR=%s: edit DATA_DIR at the top of %s\n' "$DATA_DIR" "$0" >&2
  exit 2
fi
check_fixes || exit 2


# ----------------------------------------------------------------------------------------------------------------------
# The configurations to run.  A configuration is named after its set of fixes (the name run_eval.sh understands):
#   all, none, all-X-Y (every fix but X and Y), none+X+Y (only X and Y), whichever is shorter.
# ----------------------------------------------------------------------------------------------------------------------

config_name() {                    # config_name: the name of the current FIX_<id> values
  local on_list off_list id
  on_list=$(fixes_on)
  off_list=""
  for id in $ALL_IDS; do
    fix_is_on $id || off_list="$off_list $id"
  done
  off_list=${off_list# }

  if   [ -z "$off_list" ]; then  printf 'all\n'
  elif [ -z "$on_list" ];  then  printf 'none\n'
  elif [ $(wc -w <<< "$off_list") -le $(wc -w <<< "$on_list") ]; then
                                 printf 'all-%s\n' "${off_list// /-}"
  else                           printf 'none+%s\n' "${on_list// /+}"
  fi
}

CHOSEN_FIXES=$(fixes_on)
CONFIGS=""
[ $RUN_STOCK = yes ] && CONFIGS="stock"

case $MODE in

  single)
    CONFIGS="$CONFIGS $(config_name)"
    ;;

  one-by-one)
    CONFIGS="$CONFIGS none"
    for id in $CHOSEN_FIXES; do
      CONFIGS="$CONFIGS none+$id"
    done
    ;;

  leave-one-out)
    CONFIGS="$CONFIGS $(config_name)"
    for id in $CHOSEN_FIXES; do
      printf -v FIX_$id false
      CONFIGS="$CONFIGS $(config_name)"
      printf -v FIX_$id true
    done
    ;;
esac


# ----------------------------------------------------------------------------------------------------------------------
# Show the plan
# ----------------------------------------------------------------------------------------------------------------------

cat <<EOF
Fixes chosen (FIX_<ID>; the sections of scripts/eval_switches.sh explain each one):

$(print_fix_table)

Runs: $(wc -w <<< "$CONFIGS") configuration(s) x $(wc -w <<< "$EVENTS") event(s)
  configurations: ${CONFIGS# }
  events:         ${EVENTS# }

EOF


# ----------------------------------------------------------------------------------------------------------------------
# Run (or, with --dry-run, show the details of every run)
# ----------------------------------------------------------------------------------------------------------------------

if [ $DRY_RUN = 1 ]; then
  for config in $CONFIGS; do
    for event in $EVENTS; do
      printf -- '---------------- %s %s\n' $config $event
      DRY_RUN=1 $WORK_DIR/scripts/run_eval.sh $config ${event%:*} ${event#*:} | sed -n '/^fixes on/,$p'
      printf '\n'
    done
  done
  exit 0
fi

mkdir -p $DATA/eval/logs

for config in $CONFIGS; do
  for event in $EVENTS; do
    printf '%s %s %s\n' $config ${event%:*} ${event#*:}
  done
done \
| xargs -P $NJOBS -L 1 bash -c '
    log='$DATA'/eval/logs/$0_$1$2.log
    '$WORK_DIR'/scripts/run_eval.sh $0 $1 $2 > $log 2>&1
    tail -1 $log'
