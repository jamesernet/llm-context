#!/usr/bin/env bash
set -euo pipefail

# Sibling worktrees for parallel agent sessions: one worktree per brief/issue,
# one Claude Code / Codex session per worktree, no branch-switching collisions.
#
#   worktree.sh new <branch> [start-point]   create <repo>.worktrees/<slug> for <branch>
#                                            (branch is created from start-point,
#                                            default HEAD, if it doesn't exist)
#   worktree.sh ls                           list this repo's worktrees
#   worktree.sh rm <branch>                  remove the worktree (branch is kept)
#   worktree.sh path <branch>                print the worktree path and exit
#
# `path` exists so a shell wrapper can cd into a new worktree without
# recomputing the layout. A subprocess cannot change its parent's directory, so
# `new` can only ever tell you where it put things — see the `wt` function in
# workstation's config/zsh/functions.zsh, which uses this to do the cd for you.
# Keeping the computation here means the wrapper cannot drift from the script.
#
# Run from anywhere inside the target repo. Worktrees live NEXT TO the repo
# (…/<org>/<repo>.worktrees/<slug>), never inside it. Slug = branch with
# "/" flattened to "-". The pre-commit branch backstop lives in the main
# repo's .git and applies to every worktree automatically.

usage() {
  grep '^#   ' "$0" | sed 's/^#  //'
  exit 1
}

cmd="${1:-}"
root="$(git rev-parse --show-toplevel)"
repo="$(basename "$root")"
wt_root="$(dirname "$root")/$repo.worktrees"

case "$cmd" in
  new)
    branch="${2:?usage: worktree.sh new <branch> [start-point]}"
    slug="${branch//\//-}"
    path="$wt_root/$slug"
    mkdir -p "$wt_root"
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      git worktree add "$path" "$branch"
    else
      git worktree add -b "$branch" "$path" "${3:-HEAD}"
    fi
    echo
    echo "worktree ready: $path"
    echo "next: cd \"$path\" and start the agent session there."
    ;;
  ls)
    git worktree list
    ;;
  path)
    branch="${2:?usage: worktree.sh path <branch>}"
    slug="${branch//\//-}"
    echo "$wt_root/$slug"
    ;;
  rm)
    branch="${2:?usage: worktree.sh rm <branch>}"
    slug="${branch//\//-}"
    git worktree remove "$wt_root/$slug"
    echo "removed $wt_root/$slug (branch \"$branch\" kept — git branch -d when merged)"
    ;;
  *)
    usage
    ;;
esac
