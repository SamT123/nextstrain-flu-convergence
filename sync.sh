#!/usr/bin/env bash
# Move code out to acmacs, one subtype's results and build state back, outputs
# to the web.
#   ./sync.sh push             code -> acmacs (mirror, minus .syncignore)
#   ./sync.sh pull <subtype>   that subtype's results, log and store <- acmacs
#   ./sync.sh publish          results/ -> notebooks, then fix permissions
# All three take extra rsync arguments, e.g. -n for a dry run.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .runenv ] && . ./.runenv

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# _targets.yaml is the subtype registry; adding one there is the only edit
SUBTYPES=$(sed -n 's/^\([A-Za-z0-9_-]*\):.*/\1/p' _targets.yaml | xargs)

requireSubtype() {
  case " $SUBTYPES " in
    *" ${1:-} "*) return 0 ;;
  esac
  echo "subtype must be one of $SUBTYPES, got '${1:-}'" >&2
  exit 2
}

# The server checkout has no .git, so the commit travels as a file that
# buildProvenance() reads. results/ is excluded because the pipeline rewrites
# tracked files there, which would make every build look dirty.
writeGitInfo() {
  local dirty=false
  [ -n "$(git status --porcelain -- . ':(exclude)results')" ] && dirty=true
  printf '{\n  "commit": "%s",\n  "dirty": %s\n}\n' \
    "$(git rev-parse HEAD)" "$dirty" > repo_git_info.json
}

# A push must wait for every subtype; a pull only for the one it fetches, since
# the stores and results directories are disjoint.
assertIdle() {
  local active
  # push passes nothing, matching every session, including a pre-subtype 'nfc'
  active=$(ssh "$REMOTE_HOST" \
    "tmux ls 2>/dev/null | grep '^$SESSION${1:+-$1:}' || true")
  if [ -n "$active" ]; then
    echo "a build is active: $active" >&2
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
    requireSubtype "${1:-}"
    subtype="$1"
    shift
    assertIdle "$subtype"
    # rsync creates the last missing component of a destination, not two
    mkdir -p "_targets/$subtype"
    rsync -a "$@" \
      "$REMOTE_HOST:$REMOTE_DIR/results/$subtype/" "results/$subtype/"
    # objects before the index: an interrupted pull then leaves a store whose
    # index promises less than it holds, which targets handles by rebuilding
    rsync -a "$@" --exclude=meta \
      "$REMOTE_HOST:$REMOTE_DIR/_targets/$subtype/" "_targets/$subtype/"
    rsync -a "$@" "$REMOTE_HOST:$REMOTE_DIR/_targets/$subtype/meta/" \
      "_targets/$subtype/meta/"
    # last: a subtype built before this log existed must not fail the pull
    rsync -a "$@" "$REMOTE_HOST:$REMOTE_DIR/logs/run-$subtype.log" logs/
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
    echo "usage: $(basename "$0") {push|publish} [rsync args]" >&2
    echo "       $(basename "$0") pull <subtype> [rsync args]" >&2
    exit 2
    ;;
esac
