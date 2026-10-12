#!/bin/bash
# Open a shell, or run one command, inside the Fermilab SL7 container, with dunesw v10_26_00d00 (e26:prof) set up.
#
#   env/in-sl7.sh [--host wcgpu1|dunegpvm]                  an interactive shell in the container; "exit" leaves it
#   env/in-sl7.sh [--host wcgpu1|dunegpvm] <command ...>    run <command> in the container, then leave
#
# The container lives as long as the shell or the command: it starts, runs it, and is gone afterwards.
#
# Examples:
#   env/in-sl7.sh                                     shell with lar, root, the dunesw fcl files
#   OPDEV=$DATA_DIR/evaldev env/in-sl7.sh             the same, with the patched build set up
#   env/in-sl7.sh lar --version
#   env/in-sl7.sh --host dunegpvm python3 analysis/eval_dump.py ...
#   SL7_HOST=dunegpvm scripts/run_fixes.sh sol:0      (scripts that call this one pass the host through SL7_HOST)
#
# Why a container: dunesw v10 is built for SL7 (glibc 2.17), and wcgpu1 (Debian 12) and the dunegpvm machines
# (AlmaLinux 9) are newer, so every LArSoft command runs inside SL7.
#
# Directories the container sees:
#   always     the home directory, the current directory, /cvmfs, and DATA_DIR (below)
#   wcgpu1     + /nfs/data
#   dunegpvm   + /exp  /nashome  /pnfs
# The container /tmp is CONTAINER_TMP_DIR (below; empty: the host /tmp).
# A directory the machine does not have is skipped (binding a missing directory kills the container).  The script
# creates DATA_DIR and CONTAINER_TMP_DIR if they do not exist.
# The host is taken from, in this order: the --host argument, the SL7_HOST variable, the machine name.
#
# Optional variables:
#   SL7_SETUP=none    start the bare container, without the dunesw setup (the build scripts set up mrb themselves)
#   OPDEV=<dir>       also set up the local build of the mrb area <dir> (localProducts + mrbslp)
#   SL7_BINDS=a,b     more host directories to make visible
#   SL7_IMAGE=<path>  another container image

DUNESW_VERSION=v10_26_00d00
DUNESW_QUALIFIERS=e26:prof
CONTAINER_IMAGE=${SL7_IMAGE:-/cvmfs/singularity.opensciencegrid.org/fermilab/fnal-dev-sl7:latest}
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR=$WORK_DIR/data                           # EDIT: where the data is saved; made visible in the container
CONTAINER_TMP_DIR=/home/rrazakami/work/LE_study/FD-LE/tmp                           # EDIT: existing directory used as /tmp in the container;
                                                 #       empty = the host /tmp (too small on wcgpu1)


# ----------------------------------------------------------------------------------------------------------------------
# 1. Which host
# ----------------------------------------------------------------------------------------------------------------------

if [ "$1" = "--host" ]; then
  SL7_HOST=$2
  shift 2
fi

if [ -z "${SL7_HOST:-}" ]; then
  case "$(hostname)" in
    wcgpu*)                SL7_HOST=wcgpu1 ;;
    dunegpvm*|dunebuild*)  SL7_HOST=dunegpvm ;;
  esac
fi

case "${SL7_HOST:-}" in
  wcgpu1)
    HOST_DIRECTORIES="/cvmfs /nfs/data"
    ;;
  dunegpvm)
    HOST_DIRECTORIES="/cvmfs /exp /nashome /pnfs"
    ;;
  *)
    printf 'in-sl7.sh: unknown host "%s" (machine %s); use --host wcgpu1 or --host dunegpvm\n' \
      "${SL7_HOST:-}" "$(hostname)" >&2
    exit 2
    ;;
esac

export SL7_HOST

if [ $# = 0 ]; then                        # no command: an interactive shell (--norc: keep the dunesw setup as is)
  export PS1="[sl7 $SL7_HOST] \w \$ "
  set -- /bin/bash --norc
fi


# ----------------------------------------------------------------------------------------------------------------------
# 2. Outside the container: start it, and run this same script inside it
# ----------------------------------------------------------------------------------------------------------------------

if [ -z "${APPTAINER_NAME:-}" ]; then

  # DATA_DIR and CONTAINER_TMP_DIR are created if they do not exist; if that fails, the container starts without them
  if [ -n "$DATA_DIR" ] && ! mkdir -p "$DATA_DIR" 2> /dev/null; then
    printf 'in-sl7.sh: cannot create DATA_DIR=%s (edit it at the top of env/in-sl7.sh)\n' "$DATA_DIR" >&2
  fi

  BIND_OPTIONS=""
  for directory in $HOST_DIRECTORIES $DATA_DIR ${SL7_BINDS//,/ }; do
    if [ -d "$directory" ] && [[ " $BIND_OPTIONS " != *" -B $directory "* ]]; then     # each one once
      BIND_OPTIONS="$BIND_OPTIONS -B $directory"
    fi
  done

  if [ -n "$CONTAINER_TMP_DIR" ]; then
    if mkdir -p "$CONTAINER_TMP_DIR" 2> /dev/null; then
      BIND_OPTIONS="$BIND_OPTIONS -B $CONTAINER_TMP_DIR:/tmp"
    else
      printf 'in-sl7.sh: cannot create CONTAINER_TMP_DIR=%s, using the host /tmp\n' "$CONTAINER_TMP_DIR" >&2
    fi
  fi

  exec apptainer exec $BIND_OPTIONS "$CONTAINER_IMAGE" /bin/bash "$0" "$@"
fi


# ----------------------------------------------------------------------------------------------------------------------
# 3. Inside the container: set up dunesw (and the local build, if OPDEV is set), then run the command
# ----------------------------------------------------------------------------------------------------------------------

if [ "${SL7_SETUP:-dunesw}" != none ]; then

  source /cvmfs/dune.opensciencegrid.org/products/dune/setup_dune.sh > /dev/null 2>&1

  if ! setup dunesw $DUNESW_VERSION -q $DUNESW_QUALIFIERS > /dev/null 2>&1; then
    printf 'in-sl7.sh: setup dunesw %s -q %s failed\n' $DUNESW_VERSION $DUNESW_QUALIFIERS >&2
    exit 90
  fi

  if [ -n "${OPDEV:-}" ]; then
    source $OPDEV/localProducts*/setup > /dev/null 2>&1
    mrbslp > /dev/null 2>&1
  fi
fi

exec "$@"
