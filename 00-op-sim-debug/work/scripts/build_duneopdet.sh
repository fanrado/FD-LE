#!/bin/bash
# Build duneopdet v10_26_00d00 with the light-simulation fixes (bugs B, C, D, E, N1), against dunesw v10_26_00d00.
#
#   scripts/build_duneopdet.sh          (~10 min the first time, ~1 min after; restarts itself inside the SL7 container)
#
# Steps:
#   1. mrb newDev: build and localProducts in $DATA_DIR/opdev, sources in $SOURCE_DIR/srcs
#   2. clone DUNE/duneopdet at tag v10_26_00d00 into $SOURCE_DIR/srcs/duneopdet
#   3. apply patches/duneopdet-light-sim-fixes.patch (it also applies to duneopdet develop, as of 2026-10)
#   4. mrb install
#   5. the unit test (ctest: FocusList_test)
#
# Steps 2-3 run only once: delete $SOURCE_DIR/srcs/duneopdet to start again from a clean clone.
# Use the build with:   OPDEV=$DATA_DIR/opdev env/in-sl7.sh <command>
#
# Optional variables:
#   OPDEV=<dir>       mrb area (default $DATA_DIR/opdev)
#   PATCH=<file>      another patch;  PATCH=none builds the unmodified tag
#   NJ=<n>            parallel compile jobs (default 12)
#   SL7_HOST=<host>   wcgpu1 or dunegpvm (see env/in-sl7.sh)
#
# Logs, in the mrb area: newdev.log, uc.log, setenv.log, build.log, test.log; build-source.txt lists the changed files.

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR=$WORK_DIR/data                           # EDIT: absolute path of the directory where the data is saved
SOURCE_DIR=$DATA_DIR/opdev                       # EDIT: absolute path of the directory where the git clone is
                                                 #       saved: mrb puts it in $SOURCE_DIR/srcs/duneopdet

if ! mkdir -p "$DATA_DIR"; then                   # create it if it does not exist
  printf 'cannot create DATA_DIR=%s: edit DATA_DIR at the top of %s\n' "$DATA_DIR" "$0" >&2
  exit 2
fi
if ! mkdir -p "$SOURCE_DIR"; then                 # create it if it does not exist
  printf 'cannot create SOURCE_DIR=%s: edit SOURCE_DIR at the top of %s\n' "$SOURCE_DIR" "$0" >&2
  exit 2
fi

if [ -z "${APPTAINER_NAME:-}" ]; then
  SL7_BINDS=$DATA_DIR,$SOURCE_DIR SL7_SETUP=none exec $WORK_DIR/env/in-sl7.sh /bin/bash "$0" "$@"
fi

DUNE_VERSION=v10_26_00d00
DUNE_QUALIFIERS=e26:prof
MRB_AREA=${OPDEV:-$DATA_DIR/opdev}
PATCH=${PATCH:-$WORK_DIR/patches/duneopdet-light-sim-fixes.patch}
NJ=${NJ:-12}

fail() {
  printf 'build_duneopdet.sh: %s\n' "$1" >&2
  exit "$2"
}

say() {                                                            # a progress line, with the time
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"
}


# --- set up dunesw and mrb -------------------------------------------------------------------------------------------

say "setting up dunesw $DUNE_VERSION and mrb"

source /cvmfs/dune.opensciencegrid.org/products/dune/setup_dune.sh > /dev/null 2>&1

setup dunesw $DUNE_VERSION -q $DUNE_QUALIFIERS > /dev/null 2>&1   || fail "dunesw setup failed" 3
setup mrb > /dev/null 2>&1
export MRB_PROJECT=larsoft


# --- 1. the mrb area -------------------------------------------------------------------------------------------------

mkdir -p $MRB_AREA
cd $MRB_AREA                                                       || fail "cannot enter $MRB_AREA" 3

say "mrb area: $MRB_AREA"

if ! ls -d localProducts* > /dev/null 2>&1; then
  say "creating the mrb area"
  mrb newDev -v $DUNE_VERSION -q $DUNE_QUALIFIERS -S $SOURCE_DIR -f > newdev.log 2>&1   || fail "mrb newDev failed (newdev.log)" 4
fi

source localProducts*/setup > /dev/null 2>&1


# --- 2-3. clone and patch (once) -------------------------------------------------------------------------------------

if [ ! -d $MRB_SOURCE/duneopdet ]; then                           # MRB_SOURCE = $SOURCE_DIR/srcs

  say "cloning duneopdet $DUNE_VERSION into $MRB_SOURCE/duneopdet"
  git clone -q -b $DUNE_VERSION https://github.com/DUNE/duneopdet.git $MRB_SOURCE/duneopdet   || fail "git clone failed" 5

  if [ "$PATCH" != none ]; then
    say "applying $(basename $PATCH)"
    git -C $MRB_SOURCE/duneopdet apply $PATCH                             || fail "patch $PATCH does not apply" 6
  fi

  (cd $MRB_SOURCE && mrb uc > $MRB_AREA/uc.log 2>&1)                             || fail "mrb uc failed (uc.log)" 7
fi

git -C $MRB_SOURCE/duneopdet status --porcelain > build-source.txt


# --- 4. build --------------------------------------------------------------------------------------------------------

mrbsetenv > setenv.log 2>&1                                        || fail "mrbsetenv failed (setenv.log)" 8

say "compiling with $NJ jobs (~10 min the first time, ~1 min after); full log: $MRB_AREA/build.log"

# the whole output goes to build.log; the screen shows only the percentage, on one line
mrb i -j$NJ 2>&1 \
  | tee build.log \
  | grep --line-buffered -o '\[ *[0-9]*%\]' \
  | while read -r percent; do printf '\r  compiled %s' "$percent"; done
build_status=${PIPESTATUS[0]}
printf '\n'

if [ $build_status != 0 ]; then
  say "build FAILED (exit code $build_status): see the end of $MRB_AREA/build.log"
  exit $build_status
fi

say "finished: duneopdet built and installed in $MRB_AREA"
say "use it with:  OPDEV=$MRB_AREA env/in-sl7.sh"


# # --- 5. unit test ----------------------------------------------------------------------------------------------------

# (cd $MRB_BUILDDIR/duneopdet && ctest --output-on-failure > $MRB_AREA/test.log 2>&1)
# test_status=$?
# printf 'unit test: exit code %s   (%s/test.log)\n' $test_status $MRB_AREA
# exit $test_status
