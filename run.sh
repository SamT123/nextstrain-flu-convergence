#!/usr/bin/env bash
# Build one subtype's LCR table here, or on acmacs in a detached tmux session.
#   ./run.sh local  <subtype> [target]  build here, in the foreground
#   ./run.sh remote <subtype> [target]  build on acmacs, logging to logs/
#   ./run.sh watch  <subtype>           follow that subtype's log
#   ./run.sh status                     which builds are alive, and where
# <subtype> travels as TAR_PROJECT; the three builds are independent and may run
# at once. Machine-local settings come from .runenv (see .runenv.example).
set -euo pipefail
cd "$(dirname "$0")"

[ -f .runenv ] && . ./.runenv

[ -n "${ALIGNMENT_PATH:-}" ] &&
  { echo "ALIGNMENT_PATH is gone: set ALIGNMENT_ROOT in .runenv" >&2; exit 1; }

# _targets.yaml is the subtype registry; adding one there is the only edit
SUBTYPES=$(sed -n 's/^\([A-Za-z0-9_-]*\):.*/\1/p' _targets.yaml | xargs)

requireSubtype() {
  case " $SUBTYPES " in
    *" ${1:-} "*) return 0 ;;
  esac
  echo "subtype must be one of $SUBTYPES, got '${1:-}'" >&2
  exit 2
}

runLocal() {
  local subtype="$1" target="${2:-}"
  local log="logs/run-$subtype.log"
  export TAR_PROJECT="$subtype"

  eval "$("${CONDA_BIN:-conda}" shell.bash hook)"
  conda activate "${CONDA_ENV:-nextstrain-flu-convergence}"
  if [ -n "${R_PREFIX:-}" ]; then
    [ -x "$R_PREFIX/bin/Rscript" ] ||
      { echo "no Rscript under R_PREFIX=$R_PREFIX" >&2; exit 1; }
    # Rscript ignores PATH: its R home is compiled in
    export PATH="$R_PREFIX/bin:$PATH" RHOME="$R_PREFIX/lib/R"
  fi

  local cmd="targets::tar_make(${target:+names = \"$target\"})"
  [ -n "${RENV_RESTORE:-}" ] && cmd="renv::restore(prompt = FALSE); $cmd"

  mkdir -p logs
  local status=0
  ${SRUN_OPTS:+srun $SRUN_OPTS} Rscript -e "$cmd" 2>&1 | tee "$log" || status=$?
  # the only record that a build finished rather than died
  echo "[run.sh] exit $status" | tee -a "$log"
  return "$status"
}

case "${1:-}" in
  local)
    shift
    requireSubtype "${1:-}"
    # .git is a file, not a directory, inside a worktree
    if git rev-parse --git-dir >/dev/null 2>&1; then ./sync.sh gitinfo; fi
    runLocal "$1" "${2:-}"
    ;;

  remote)
    shift
    requireSubtype "${1:-}"
    ssh "$REMOTE_HOST" bash -s <<REMOTE
set -euo pipefail
cd "$REMOTE_DIR"
# tmux refuses a duplicate session name, which is the per-subtype build lock
tmux new-session -d -s "$SESSION-$1" "./run.sh local $1 ${2:-}" ||
  { echo "a $1 build is already active: ./run.sh watch $1" >&2; exit 1; }
REMOTE
    echo "launched. watch: ./run.sh watch $1"
    ;;

  watch)
    shift
    requireSubtype "${1:-}"
    ssh "$REMOTE_HOST" "tail -n +1 -F '$REMOTE_DIR/logs/run-$1.log'"
    ;;

  status)
    ssh "$REMOTE_HOST" "tmux ls 2>/dev/null | grep '^$SESSION' ||
      echo 'no build active'; squeue -u \$USER"
    ;;

  *)
    echo "usage: $(basename "$0") {local|remote|watch} <subtype> [target]" >&2
    echo "       $(basename "$0") status" >&2
    exit 2
    ;;
esac
