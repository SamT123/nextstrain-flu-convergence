#!/usr/bin/env bash
# Move code out to acmacs, results and the build state back, outputs to the web.
#   ./sync.sh push    [rsync args]  code -> acmacs (mirror, minus .syncignore)
#   ./sync.sh pull    [rsync args]  results/, logs/, _targets/ <- acmacs
#   ./sync.sh publish [rsync args]  results/ -> notebooks, then fix permissions
set -euo pipefail
cd "$(dirname "$0")"

[ -f .runenv ] && . ./.runenv

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# The server checkout has no .git, so the commit travels as a file that
# buildProvenance() reads. results/ is excluded because the pipeline rewrites
# tracked files there, which would make every build look dirty.
writeGitInfo() {
  local dirty=false
  [ -n "$(git status --porcelain -- . ':(exclude)results')" ] && dirty=true
  printf '{\n  "commit": "%s",\n  "dirty": %s\n}\n' \
    "$(git rev-parse HEAD)" "$dirty" > repo_git_info.json
}

assertIdle() {
  if ssh "$REMOTE_HOST" "tmux has-session -t '$SESSION' 2>/dev/null"; then
    echo "a build is active: watch it with ./run.sh watch" >&2
    exit 1
  fi
}

case "${1:-}" in
  gitinfo)
    writeGitInfo
    ;;

  push)
    shift
    assertIdle
    case " $* " in *" -n "*|*" --dry-run "*) ;; *) writeGitInfo ;; esac
    rsync -av --delete --exclude-from=.syncignore "$@" \
      ./ "$REMOTE_HOST:$REMOTE_DIR/"
    ;;

  pull)
    shift
    assertIdle
    for dir in results logs; do
      rsync -a "$@" "$REMOTE_HOST:$REMOTE_DIR/$dir/" "$dir/"
    done
    # objects before the index: an interrupted pull then leaves a store whose
    # index promises less than it holds, which targets handles by rebuilding
    rsync -a "$@" --exclude=meta "$REMOTE_HOST:$REMOTE_DIR/_targets/" _targets/
    rsync -a "$@" "$REMOTE_HOST:$REMOTE_DIR/_targets/meta/" _targets/meta/
    ;;

  publish)
    shift
    # tree/ is 98% of results/ and is build scratch, not a deliverable
    rsync -rlt --delete --exclude="tree/" --exclude=".DS_Store" "$@" \
      results/ "$PUBLISH_HOST:$PUBLISH_DIR/"
    # Apache serves as group www-data; only root can set that group for us.
    # Setgid on directories so ones rsync adds later inherit it.
    publish_abs="/syn/$PUBLISH_USER/$PUBLISH_DIR" # behind the ~/html symlink
    ssh -t "$PUBLISH_HOST" "sudo sh -c '
      chown -R $PUBLISH_USER:www-data $publish_abs &&
      find $publish_abs -type d -exec chmod 2771 {} + &&
      find $publish_abs -type f -exec chmod 660 {} +'"
    ;;

  *)
    echo "usage: $(basename "$0") {push|pull|publish} [rsync args]" >&2
    exit 2
    ;;
esac
