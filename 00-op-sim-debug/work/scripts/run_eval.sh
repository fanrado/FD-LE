#!/bin/bash
# Run the FD-VD light simulation of one event with a chosen set of fixes on and the others off (PLAN.md section 2).
# For everyday use, scripts/run_fixes.sh is easier: it calls this script.
#
#   scripts/run_eval.sh <config> <sol|mix> <idx>          (restarts itself inside the SL7 container)
#
# <config>
#   stock          CVMFS duneopdet, stock fcl (no switch written)
#   none           patched build ($DATA_DIR/evaldev, scripts/build_eval.sh), every fix off: must reproduce stock
#   all            every fix on
#   all-X[-Y..]    every fix on except X, Y, ...  (the effect of bug X in an otherwise fixed simulation)
#   none+X[+Y..]   only X, Y, ... on              (the effect of fixing X alone)
# Fix ids and their switches: scripts/eval_switches.sh.   N4 N71 N72 | B C D E N1 N2 N3 N6 | F N5 A
#
# Input: $DATA_DIR/events/<sol|mix>/evt<idx>/ from scripts/run_chain.sh (reco.root, job fcls; g4s1.root, kept with
# KEEP_INTERMEDIATE=1, only for the g4 stage).  All paths below are under DATA_DIR.
#
# Stages.  Each is cached in $DATA_DIR/eval/cache/<stage>/<key>/<sol|mix>/evt<idx>, where <key> names the fixes that are on
# up to that stage, so configurations that agree up to a stage share its output:
#   g4    only if N4, N71 or N72 is on: PDFastSimAr(+External) on g4s1.root with the random-engine states restored
#         from its rns snapshot, then the event's own stage-2 job (PDFastSimXe(+External)).  With these fixes off,
#         both reproduce the stored photons bit for bit; otherwise the stored photons of reco.root are used.
#   det   light detsim (fcl/detsim_light_rerun.fcl, the event's detsim seed) + the det switches
#   reco  ophit10ppm, opflash10ppm, solarflash + the reco switches; then analysis/dump_light.py -> light.npz and
#         analysis/eval_dump.py -> eval.npz (snippet hashes, OpHits, flash members, DivRec rows near t = 0)
#
# Result: $DATA_DIR/eval/run/<config>/<sol|mix>/evt<idx> links to the reco directory.  Its stages_<config>.txt lists the
# fixes that were on and the three cache directories (whose g4a.fcl, g4b.fcl, detsim.fcl, reco.fcl hold the exact
# switch lines).
#
# Optional variables:
#   DRY_RUN=1      print the fixes ON/OFF, the switch lines and the cache directories; run nothing
#   FORCE_G4=1     run the g4 stage even with N4, N71, N72 off (to check that it reproduces the stored photons)
#   SOLARFLASH=1   run solarflash also on mixed events with F on (otherwise skipped: ~1 hour per event)
#   RUNNAME=<n>    link the result as eval/run/<n>/... instead of eval/run/<config>/...
#   SL7_HOST=<h>   wcgpu1 or dunegpvm (see env/in-sl7.sh)

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR=$WORK_DIR/data                           # EDIT: absolute path of the directory where the data is saved
DATA=$DATA_DIR

CONFIG=$1
SAMPLE=$2
EVENT_INDEX=$3

if [ -z "$EVENT_INDEX" ]; then
  sed -n '2,/^$/p' "$0"
  exit 2
fi

if ! mkdir -p "$DATA_DIR"; then                   # create it if it does not exist
  printf 'cannot create DATA_DIR=%s: edit DATA_DIR at the top of %s\n' "$DATA_DIR" "$0" >&2
  exit 2
fi
source $WORK_DIR/scripts/eval_switches.sh


# ----------------------------------------------------------------------------------------------------------------------
# Which fixes are on: set every FIX_<id> from <config>
# ----------------------------------------------------------------------------------------------------------------------

check_id() {
  if ! grep -qw -- "$1" <<< "$ALL_IDS"; then
    printf 'unknown fix id "%s"; the ids are: %s\n' "$1" "$ALL_IDS" >&2
    exit 2
  fi
}

case $CONFIG in
  stock|none)
    set_all_fixes false
    ;;
  all)
    set_all_fixes true
    ;;
  all-*)
    set_all_fixes true
    for id in $(tr '-' ' ' <<< "${CONFIG#all-}"); do
      check_id $id
      printf -v FIX_$id false
    done
    ;;
  none+*)
    set_all_fixes false
    for id in $(tr '+' ' ' <<< "${CONFIG#none+}"); do
      check_id $id
      printf -v FIX_$id true
    done
    ;;
  *)
    printf 'unknown config "%s": use stock, none, all, all-X or none+X\n' "$CONFIG" >&2
    exit 2
    ;;
esac

FIXES_ON=$(fixes_on)

if [ $CONFIG = stock ]; then
  BUILD=stock
else
  BUILD=evaldev
  export OPDEV=${OPDEV:-$DATA/evaldev}
fi


# ----------------------------------------------------------------------------------------------------------------------
# Cache directories.  The key of a stage names the fixes on up to that stage, e.g. "N4.N71", "B.C.D", "F.N5.A".
# ----------------------------------------------------------------------------------------------------------------------

stage_key() {                               # stage_key <ids>: the ids that are on, joined by "."
  local list
  list=$(fixes_on "$@")
  printf '%s\n' "${list// /.}"
}

G4_KEY=$(stage_key $G4_IDS)
DET_KEY_PART=$(stage_key $DET_IDS)
RECO_KEY_PART=$(stage_key $RECO_IDS)

RUN_G4=no
if [ $CONFIG != stock ] && { [ -n "$G4_KEY" ] || [ "${FORCE_G4:-0}" = 1 ]; }; then
  RUN_G4=yes
fi

if [ $RUN_G4 = yes ]; then
  G4_DIR=$DATA/eval/cache/g4/${G4_KEY:-off}/$SAMPLE/evt$EVENT_INDEX
  G4_TAG=${G4_KEY:-off}
else
  G4_DIR=""
  G4_TAG=stored
fi

DET_KEY=$BUILD-g4_$G4_TAG-det_${DET_KEY_PART:-off}
DET_DIR=$DATA/eval/cache/det/$DET_KEY/$SAMPLE/evt$EVENT_INDEX

RECO_KEY=$DET_KEY-reco_${RECO_KEY_PART:-off}
RECO_DIR=$DATA/eval/cache/reco/$RECO_KEY/$SAMPLE/evt$EVENT_INDEX

INPUT_DIR=$DATA/events/$SAMPLE/evt$EVENT_INDEX
RUN_LINK=$DATA/eval/run/${RUNNAME:-$CONFIG}/$SAMPLE/evt$EVENT_INDEX


# ----------------------------------------------------------------------------------------------------------------------
# DRY_RUN=1: show what would be run, and stop
# ----------------------------------------------------------------------------------------------------------------------

if [ "${DRY_RUN:-0}" = 1 ]; then
  cat <<EOF
config $CONFIG    event $SAMPLE $EVENT_INDEX    build $BUILD

$(print_fix_table)

fixes on: ${FIXES_ON:-(none)}

EOF
  if [ $CONFIG = stock ]; then
    printf 'switch lines: none (stock fcl)\n\n'
  else
    printf 'switch lines written into the job fcls:\n'
    [ $RUN_G4 = yes ] && printf '  g4 stage 1:\n%s\n  g4 stage 2:\n%s\n' "$(fcl_lines N4 N71 | sed 's/^/    /')" \
                                                                         "$(fcl_lines N72 | sed 's/^/    /')"
    printf '  det:\n%s\n  reco:\n%s\n\n' "$(fcl_lines $DET_IDS | sed 's/^/    /')" "$(fcl_lines $RECO_IDS | sed 's/^/    /')"
  fi
  cat <<EOF
cache directories:
  g4    ${G4_DIR:-(not run: the photons stored in $INPUT_DIR/reco.root)}
  det   $DET_DIR
  reco  $RECO_DIR
result: $RUN_LINK
EOF
  exit 0
fi


# ----------------------------------------------------------------------------------------------------------------------
# Into the container
# ----------------------------------------------------------------------------------------------------------------------

if [ -z "${APPTAINER_NAME:-}" ]; then
  SL7_BINDS=$DATA_DIR exec $WORK_DIR/env/in-sl7.sh /bin/bash "$0" "$@"
fi

if ! grep -q DONE $INPUT_DIR/status.txt 2> /dev/null; then
  printf '%s %s %s: input event not ready (%s): scripts/run_chain.sh %s %s\n' \
    $CONFIG $SAMPLE $EVENT_INDEX $INPUT_DIR $SAMPLE $EVENT_INDEX
  exit 3
fi
if [ $RUN_G4 = yes ] && [ ! -f $INPUT_DIR/g4s1.root ] && [ ! -f $G4_DIR/done ]; then
  printf '%s %s %s: the G4 fixes need %s/g4s1.root: KEEP_INTERMEDIATE=1 scripts/run_chain.sh %s %s\n' \
    $CONFIG $SAMPLE $EVENT_INDEX $INPUT_DIR $SAMPLE $EVENT_INDEX
  exit 3
fi

export FHICL_FILE_PATH="$WORK_DIR/fcl:$INPUT_DIR:$FHICL_FILE_PATH"

# one job at a time per cache directory: other jobs wait for the lock, then find the "done" file
lock()   { mkdir -p $(dirname $1); until mkdir $1.lock 2> /dev/null; do sleep 10; done; }
unlock() { rmdir $1.lock; }
fail()   { unlock $1; printf '%s %s %s %s FAILED (%s)\n' $CONFIG $SAMPLE $EVENT_INDEX $2 $1; exit 4; }

timed()  { /usr/bin/time -f "%e s %M kB" "$@"; }                     # elapsed time and memory, into the log


# ----------------------------------------------------------------------------------------------------------------------
# Stage g4: G4 light reruns (only if N4, N71 or N72 is on)
# ----------------------------------------------------------------------------------------------------------------------

if [ $RUN_G4 = yes ]; then

  lock $G4_DIR
  if [ ! -f $G4_DIR/done ]; then
    mkdir -p $G4_DIR

    cat > $G4_DIR/g4a.fcl <<EOF
#include "supernova_g4stage1_dunevd10kt_1x8x14_3view_30deg.fcl"
process_name: G4Light1
source: { module_type: RootInput maxEvents: -1
          inputCommands: [ "keep *", "drop sim::OpDetBacktrackerRecords_*_*_*", "drop sim::SimPhotonsLites_*_*_*" ] }
physics.simulate: [ PDFastSimAr, PDFastSimArExternal ]
outputs.out1.fileName: "g4a.root"
outputs.out1.outputCommands: [ "keep *" ]
services.NuRandomService.policy: "random"
services.NuRandomService.masterSeed: 1      # not used: every engine is restored from the stage-1 snapshot
services.RandomNumberGenerator.restoreStateLabel: "rns::SupernovaG4Stage1"
$(fcl_lines N4 N71)
EOF

    cat > $G4_DIR/g4b.fcl <<EOF
# the event's own stage-2 job: same seeds
#include "job_g4s2.fcl"
process_name: G4Light2
outputs.out1.fileName: "g4.root"
outputs.out1.outputCommands: [ "keep *", "drop sim::SimEnergyDeposits_*_*_*", "drop sim::SimChannels_*_*_*" ]
$(fcl_lines N72)
EOF

    ( cd $G4_DIR \
      && timed lar -c g4a.fcl -s $INPUT_DIR/g4s1.root -n 1 > g4a.log 2>&1 \
      && timed lar -c g4b.fcl -s g4a.root -n 1 > g4b.log 2>&1 \
      && rm -f g4a.root \
      && touch done ) \
    || fail $G4_DIR g4
  fi
  unlock $G4_DIR

  DET_INPUT=$G4_DIR/g4.root
else
  DET_INPUT=$INPUT_DIR/reco.root
fi


# ----------------------------------------------------------------------------------------------------------------------
# Stage det: light detsim
# ----------------------------------------------------------------------------------------------------------------------

lock $DET_DIR
if [ ! -f $DET_DIR/done ]; then
  mkdir -p $DET_DIR

  DETSIM_SEED=$(awk '/masterSeed/ {print $2}' $INPUT_DIR/job_detsim.fcl)
  DET_SWITCHES=""
  [ $CONFIG = stock ] || DET_SWITCHES=$(fcl_lines $DET_IDS)

  cat > $DET_DIR/detsim.fcl <<EOF
#include "detsim_light_rerun.fcl"
services.NuRandomService.masterSeed: $DETSIM_SEED
$DET_SWITCHES
EOF

  ( cd $DET_DIR \
    && timed lar -c detsim.fcl -s $DET_INPUT -n 1 > detsim.log 2>&1 \
    && touch done ) \
  || fail $DET_DIR detsim
fi
unlock $DET_DIR


# ----------------------------------------------------------------------------------------------------------------------
# Stage reco: OpHits and flashes, then the dumps for the analysis
# ----------------------------------------------------------------------------------------------------------------------

lock $RECO_DIR
if [ ! -f $RECO_DIR/done ]; then
  mkdir -p $RECO_DIR

  SOLARFLASH_MODULE=", solarflash"
  if [ $SAMPLE = mix ] && fix_is_on F && [ "${SOLARFLASH:-0}" != 1 ]; then
    SOLARFLASH_MODULE=""
  fi
  RECO_SWITCHES=""
  [ $CONFIG = stock ] || RECO_SWITCHES=$(fcl_lines $RECO_IDS)

  cat > $RECO_DIR/reco.fcl <<EOF
#include "SolarOpFlash.fcl"
#include "standard_reco_dunevd10kt_1x8x14_3view_30deg.fcl"
process_name: EvalReco
physics.producers.solarflash: @local::solar_opflash_dunevd10kt_1x8x14_3view_30deg
physics.reco: [ rns, ophit10ppm, opflash10ppm$SOLARFLASH_MODULE ]
physics.trigger_paths: [ reco ]
physics.end_paths: [ stream1 ]
outputs.out1.fileName: "reco.root"
outputs.out1.outputCommands: [ "drop *", "keep *_*_*_EvalReco" ]
$RECO_SWITCHES
EOF

  ( cd $RECO_DIR \
    && lar -c reco.fcl -s $DET_DIR/detsim_rerun.root -n 1 > reco.log 2>&1 ) \
  || fail $RECO_DIR reco

  ( cd $RECO_DIR \
    && python3 $WORK_DIR/analysis/dump_light.py $DET_DIR/detsim_rerun.root reco.root $INPUT_DIR/reco.root light.npz \
         > dump.log 2>&1 \
    && python3 $WORK_DIR/analysis/eval_dump.py $DET_DIR/detsim_rerun.root reco.root eval.npz \
         > eval_dump.log 2>&1 ) \
  || fail $RECO_DIR dump

  touch $RECO_DIR/done
fi
unlock $RECO_DIR


# ----------------------------------------------------------------------------------------------------------------------
# The configuration's directory: a link to the reco cache, and the record of what was on
# ----------------------------------------------------------------------------------------------------------------------

mkdir -p $(dirname $RUN_LINK)
ln -sfn $RECO_DIR $RUN_LINK

BUILD_USED=$OPDEV
[ $CONFIG = stock ] && BUILD_USED=CVMFS

cat > $RECO_DIR/stages_${RUNNAME:-$CONFIG}.txt <<EOF
config $CONFIG
on ${FIXES_ON:-(none)}
g4 ${G4_DIR:-stored photons ($INPUT_DIR/reco.root)}
det $DET_DIR
reco $RECO_DIR
build $BUILD_USED
EOF

printf '%s %s %s ok %s\n' $CONFIG $SAMPLE $EVENT_INDEX "$(date +%T)"
