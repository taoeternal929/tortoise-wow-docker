#!/usr/bin/env bash
# Mirror this GitHub repository's branches and tags to a GitLab project.
#
#   mirror-to-gitlab.sh all             every branch and tag
#   mirror-to-gitlab.sh push   <ref>    one ref, e.g. refs/heads/main or refs/tags/v1
#   mirror-to-gitlab.sh delete <ref>    delete one ref on GitLab (it was deleted on GitHub)
#
# GitHub is the source of truth: refs are force-updated to match it. Nothing is
# deleted on GitLab except refs deleted on GitHub, so branches that only exist
# on GitLab are left alone.
#
# env: SOURCE_URL (GitHub repo), TARGET_URL (GitLab repo), GITLAB_TOKEN (for https pushes)
set -euo pipefail

mode=${1:?usage: mirror-to-gitlab.sh all|push <ref>|delete <ref>}
ref=${2:-}
: "${SOURCE_URL:?}" "${TARGET_URL:?}"
case "$mode" in
  all) ;;
  push|delete) [[ "$ref" =~ ^refs/(heads|tags)/[^[:space:]]+$ ]] || { echo "bad ref: '$ref'" >&2; exit 2; } ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q --bare "$work/mirror.git"
cd "$work/mirror.git"
if [ -n "${GITLAB_TOKEN:-}" ]; then
  # Token via a credential helper scoped to the GitLab host: never in a URL or
  # the log, and never offered to GitHub.
  origin=$(printf '%s' "$TARGET_URL" | sed -E 's#^(https?://[^/]+).*#\1#')
  git config "credential.${origin}.helper" '!f() { echo username=oauth2; echo "password=${GITLAB_TOKEN}"; }; f'
fi

push() {
  if ! git push "$TARGET_URL" "$@" 2> "$work/push.err"; then
    cat "$work/push.err" >&2
    if grep -qiE 'protected branch|not allowed to (push|force|delete)' "$work/push.err"; then
      echo "GitLab refused a protected branch. Give the token the Maintainer role, and for a" >&2
      echo "branch whose history GitHub rewrote, allow force push on it (Settings > Repository >" >&2
      echo "Protected branches)." >&2
    fi
    return 1
  fi
  cat "$work/push.err"
}

case "$mode" in
  all)
    git fetch -q --prune "$SOURCE_URL" '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
    echo ">>> mirroring $(git for-each-ref refs/heads | wc -l) branch(es) and $(git for-each-ref refs/tags | wc -l) tag(s)"
    push '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
    ;;
  push)
    git fetch -q "$SOURCE_URL" "+${ref}:${ref}"
    echo ">>> mirroring ${ref} ($(git rev-parse --short "$ref"))"
    push "+${ref}:${ref}"
    ;;
  delete)
    if git ls-remote --exit-code "$TARGET_URL" "$ref" >/dev/null 2>&1; then
      echo ">>> deleting ${ref} on GitLab (deleted on GitHub)"
      push ":${ref}"
    else
      echo ">>> ${ref} is not on GitLab; nothing to delete"
    fi
    ;;
esac
