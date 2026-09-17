#!/usr/bin/env bash
# Build the LCR table here, or on acmacs in a detached tmux session.
#   ./run.sh local  [target]  build here, in the foreground
#   ./run.sh remote [target]  build on acmacs, logging to logs/run.log
#   ./run.sh watch            follow that log
#   ./run.sh status           is a build alive, and on which node
# Machine-local settings come from .runenv (see .runenv.example).
set -euo pipefail
cd "$(dirname "$0")"

[ -f .runenv ] && . ./.runenv

LOG="logs/run.log"

runLocal() {
  eval "$("${CONDA_BIN:-conda}" shell.bash hook)"
  conda activate "${CONDA_ENV:-influenza_convergence}"
  if [ -n "${R_PREFIX:-}" ]; then
    [ -x "$R_PREFIX/bin/Rscript" ] ||
      { echo "no Rscript under R_PREFIX=$R_PREFIX" >&2; exit 1; }
    # Rscript ignores PATH: its R home is compiled in
    export PATH="$R_PREFIX/bin:$PATH" RHOME="$R_PREFIX/lib/R"
  fi

  local cmd="targets::tar_make(${1:+names = \"$1\"})"
  [ -n "${RENV_RESTORE:-}" ] && cmd="renv::restore(prompt = FALSE); $cmd"

  mkdir -p logs
  local status=0
  ${SRUN_OPTS:+srun $SRUN_OPTS} Rscript -e "$cmd" 2>&1 | tee "$LOG" || status=$?
  # the only record that a build finished rather than died
  echo "[run.sh] exit $status" | tee -a "$LOG"
  return "$status"
}

case "${1:-}" in
  local)
    shift
    # .git is a file, not a directory, inside a worktree
    if git rev-parse --git-dir >/dev/null 2>&1; then ./sync.sh gitinfo; fi
    runLocal "${1:-}"
    ;;

  remote)
    shift
    ssh "$REMOTE_HOST" bash -s <<REMOTE
set -euo pipefail
cd "$REMOTE_DIR"
# tmux refuses a duplicate session name, which is the lock against a second build
tmux new-session -d -s "$SESSION" "./run.sh local ${1:-}" ||
  { echo "a build is already active: watch it with ./run.sh watch" >&2; exit 1; }
REMOTE
    echo "launched. watch: ./run.sh watch"
    ;;

  watch)
    ssh "$REMOTE_HOST" "tail -n +1 -f '$REMOTE_DIR/$LOG'"
    ;;

  status)
    ssh "$REMOTE_HOST" "tmux has-session -t '$SESSION' 2>/dev/null &&
      echo 'build active' || echo 'no build active'; squeue -u \$USER"
    ;;

  *)
    echo "usage: $(basename "$0") {local|remote|watch|status} [target]" >&2
    exit 2
    ;;
esac
