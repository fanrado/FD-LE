#!/bin/bash
# Build duneopdet v10_26_00d00 with the light-simulation fixes (bugs B, C, D, E, N1), against dunesw v10_26_00d00.
#
#   scripts/build_duneopdet.sh          (~1-2 min with 12 cores; restarts itself inside the SL7 container)
#
# Steps:
#   1. mrb newDev in data/opdev
#   2. clone DUNE/duneopdet at tag v10_26_00d00 into data/opdev/srcs/duneopdet
#   3. apply patches/duneopdet-light-sim-fixes.patch (it also applies to duneopdet develop, as of 2026-10)
#   4. mrb install
#   5. the unit test (ctest: FocusList_test)
#
# Steps 2-3 run only once: delete data/opdev/srcs/duneopdet to start again from a clean clone.
# Use the build with:   OPDEV=data/opdev env/in-sl7.sh <command>
#
# Optional variables:
#   OPDEV=<dir>       mrb area (default data/opdev)
#   PATCH=<file>      another patch;  PATCH=none builds the unmodified tag
#   NJ=<n>            parallel compile jobs (default 12)
#   SL7_HOST=<host>   wcgpu1 or dunegpvm (see env/in-sl7.sh)
#
# Logs, in the mrb area: newdev.log, uc.log, setenv.log, build.log, test.log; build-source.txt lists the changed files.

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${APPTAINER_NAME:-}" ]; then
  SL7_SETUP=none exec $WORK_DIR/env/in-sl7.sh /bin/bash "$0" "$@"
fi

DUNE_VERSION=v10_26_00d00
DUNE_QUALIFIERS=e26:prof
MRB_AREA=${OPDEV:-$WORK_DIR/data/opdev}
PATCH=${PATCH:-$WORK_DIR/patches/duneopdet-light-sim-fixes.patch}
NJ=${NJ:-12}

fail() {
  printf 'build_duneopdet.sh: %s\n' "$1" >&2
  exit "$2"
}


# --- set up dunesw and mrb -------------------------------------------------------------------------------------------

source /cvmfs/dune.opensciencegrid.org/products/dune/setup_dune.sh > /dev/null 2>&1

setup dunesw $DUNE_VERSION -q $DUNE_QUALIFIERS > /dev/null 2>&1   || fail "dunesw setup failed" 3
setup mrb > /dev/null 2>&1
export MRB_PROJECT=larsoft


# --- 1. the mrb area -------------------------------------------------------------------------------------------------

mkdir -p $MRB_AREA
cd $MRB_AREA                                                       || fail "cannot enter $MRB_AREA" 3

if [ ! -d srcs ]; then
  mrb newDev -v $DUNE_VERSION -q $DUNE_QUALIFIERS -f > newdev.log 2>&1   || fail "mrb newDev failed (newdev.log)" 4
fi

source localProducts*/setup > /dev/null 2>&1


# --- 2-3. clone and patch (once) -------------------------------------------------------------------------------------

if [ ! -d srcs/duneopdet ]; then

  git clone -q -b $DUNE_VERSION https://github.com/DUNE/duneopdet.git srcs/duneopdet   || fail "git clone failed" 5

  if [ "$PATCH" != none ]; then
    git -C srcs/duneopdet apply $PATCH                             || fail "patch $PATCH does not apply" 6
  fi

  (cd srcs && mrb uc > ../uc.log 2>&1)                             || fail "mrb uc failed (uc.log)" 7
fi

git -C srcs/duneopdet status --porcelain > build-source.txt


# --- 4. build --------------------------------------------------------------------------------------------------------

mrbsetenv > setenv.log 2>&1                                        || fail "mrbsetenv failed (setenv.log)" 8

mrb i -j$NJ > build.log 2>&1
build_status=$?
printf 'build:     exit code %s   (%s/build.log)\n' $build_status $MRB_AREA
[ $build_status = 0 ] || exit $build_status


# --- 5. unit test ----------------------------------------------------------------------------------------------------

(cd $MRB_BUILDDIR/duneopdet && ctest --output-on-failure > $MRB_AREA/test.log 2>&1)
test_status=$?
printf 'unit test: exit code %s   (%s/test.log)\n' $test_status $MRB_AREA
exit $test_status
