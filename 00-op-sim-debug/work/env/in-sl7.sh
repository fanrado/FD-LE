#!/bin/bash
# Run a command inside the Fermilab SL7 container, with dunesw v10_26_00d00 (e26:prof) set up.
#
#   env/in-sl7.sh [--host wcgpu1|dunegpvm] <command ...>
#
# Examples:
#   env/in-sl7.sh lar --version
#   env/in-sl7.sh --host dunegpvm python3 analysis/eval_dump.py ...
#   SL7_HOST=dunegpvm scripts/run_fixes.sh sol:0      (scripts that call this one pass the host through SL7_HOST)
#
# Why a container: dunesw v10 is built for SL7 (glibc 2.17), and wcgpu1 (Debian 12) and the dunegpvm machines
# (AlmaLinux 9) are newer, so every LArSoft command runs inside SL7.
#
# The host decides which host directories the container sees, and where its /tmp is:
#
#   host       directories made visible                 container /tmp
#   wcgpu1     /cvmfs  /nfs/data                        work/data/tmp   (the host /tmp has only ~2 GB)
#   dunegpvm   /cvmfs  /exp  /nashome  /pnfs            the host /tmp
#
# The home directory and the current directory are always visible.  A directory the machine does not have is
# skipped: binding a missing directory kills the container.
# The host is taken from, in this order: the --host argument, the SL7_HOST variable, the machine name.
#
# Optional variables:
#   SL7_SETUP=none    start the bare container, without the dunesw setup (the build scripts set up mrb themselves)
#   OPDEV=<dir>       also set up the local build of the mrb area <dir> (localProducts + mrbslp)
#   SL7_BINDS=a,b     more host directories to make visible
#   SL7_TMP=<dir>     host directory to use as the container /tmp, instead of the host default above
#   SL7_IMAGE=<path>  another container image

DUNESW_VERSION=v10_26_00d00
DUNESW_QUALIFIERS=e26:prof
CONTAINER_IMAGE=${SL7_IMAGE:-/cvmfs/singularity.opensciencegrid.org/fermilab/fnal-dev-sl7:latest}
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"


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
    DEFAULT_TMP=$WORK_DIR/data/tmp
    ;;
  dunegpvm)
    HOST_DIRECTORIES="/cvmfs /exp /nashome /pnfs"
    DEFAULT_TMP=""
    ;;
  *)
    printf 'in-sl7.sh: unknown host "%s" (machine %s); use --host wcgpu1 or --host dunegpvm\n' \
      "${SL7_HOST:-}" "$(hostname)" >&2
    exit 2
    ;;
esac

export SL7_HOST

if [ $# = 0 ]; then
  printf 'usage: env/in-sl7.sh [--host wcgpu1|dunegpvm] <command ...>\n' >&2
  exit 2
fi


# ----------------------------------------------------------------------------------------------------------------------
# 2. Outside the container: start it, and run this same script inside it
# ----------------------------------------------------------------------------------------------------------------------

if [ -z "${APPTAINER_NAME:-}" ]; then

  BIND_OPTIONS=""
  for directory in $HOST_DIRECTORIES ${SL7_BINDS//,/ }; do
    if [ -d "$directory" ]; then
      BIND_OPTIONS="$BIND_OPTIONS -B $directory"
    fi
  done

  CONTAINER_TMP=${SL7_TMP:-$DEFAULT_TMP}
  if [ -n "$CONTAINER_TMP" ]; then
    mkdir -p "$CONTAINER_TMP"
    BIND_OPTIONS="$BIND_OPTIONS -B $CONTAINER_TMP:/tmp"
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
