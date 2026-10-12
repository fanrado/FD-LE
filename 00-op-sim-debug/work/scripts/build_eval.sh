#!/bin/bash
# Build dunecore and duneopdet v10_26_00d00 with every patch of patches/series, against dunesw v10_26_00d00.
# This is the build that scripts/run_fixes.sh and scripts/run_eval.sh use.
#
#   scripts/build_eval.sh               (~15-20 min with 12 cores; restarts itself inside the SL7 container)
#
# Steps:
#   1. mrb newDev in data/evaldev
#   2. clone DUNE/dunecore and DUNE/duneopdet at tag v10_26_00d00 into data/evaldev/srcs/
#   3. apply the patches listed in patches/series, in order (each one checked with git apply --check first)
#   4. mrb install
#   5. the duneopdet unit test
#
# All patches are compiled in, but each fix has an fcl switch (scripts/eval_switches.sh): the patches decide what the
# build CAN do, the switches decide what a job DOES.  With every switch off, the build reproduces the stock output.
#
# Steps 2-3 run only once: delete data/evaldev/srcs/dunecore and srcs/duneopdet to start again from clean clones.
# Use the build with:   OPDEV=data/evaldev env/in-sl7.sh <command>
#
# Optional variables:
#   OPDEV=<dir>       mrb area (default data/evaldev)
#   SERIES=<file>     another patch list (default patches/series)
#   NJ=<n>            parallel compile jobs (default 12)
#   SL7_HOST=<host>   wcgpu1 or dunegpvm (see env/in-sl7.sh)
#
# Logs, in the mrb area: newdev.log, uc.log, setenv.log, build.log, test.log; applied.txt lists the applied patches,
# build-source.txt the changed files.

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${APPTAINER_NAME:-}" ]; then
  SL7_SETUP=none exec $WORK_DIR/env/in-sl7.sh /bin/bash "$0" "$@"
fi

DUNE_VERSION=v10_26_00d00
DUNE_QUALIFIERS=e26:prof
MRB_AREA=${OPDEV:-$WORK_DIR/data/evaldev}
SERIES=${SERIES:-$WORK_DIR/patches/series}
REPOSITORIES="dunecore duneopdet"
NJ=${NJ:-12}

fail() {
  printf 'build_eval.sh: %s\n' "$1" >&2
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

if [ ! -d srcs/dunecore ] || [ ! -d srcs/duneopdet ]; then

  for repository in $REPOSITORIES; do
    git clone -q -b $DUNE_VERSION https://github.com/DUNE/$repository.git srcs/$repository 2> /dev/null \
      || fail "git clone of $repository failed" 5
  done

  # patches/series: one "<repository> <patch file>  # comment" per line
  while read -r repository patch_file comment; do

    case "$repository" in ''|'#'*) continue ;; esac

    git -C srcs/$repository apply --check $WORK_DIR/patches/$patch_file   || fail "patch $patch_file does not apply" 6
    git -C srcs/$repository apply         $WORK_DIR/patches/$patch_file
    printf '%s %s\n' $repository $patch_file >> applied.txt

  done < $SERIES

  (cd srcs && mrb uc > ../uc.log 2>&1)                             || fail "mrb uc failed (uc.log)" 7
fi

{
  cat applied.txt
  for repository in $REPOSITORIES; do
    printf '== %s\n' $repository
    git -C srcs/$repository status --porcelain
  done
} > build-source.txt


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
