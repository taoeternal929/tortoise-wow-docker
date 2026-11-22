#!/usr/bin/env bash
# Mirror this GitHub repository's branches and tags to a GitLab project.
#
#   mirror-to-gitlab.sh all             every branch and tag
#   mirror-to-gitlab.sh push   <ref>    one ref, e.g. refs/heads/main or refs/tags/v1
#   mirror-to-gitlab.sh delete <ref>    delete one ref on GitLab (it was deleted on GitHub)
#
# GitHub is the source of truth, but nothing on GitLab is overwritten blindly:
#   - a GitLab branch that is behind GitHub is fast-forwarded;
#   - a GitLab branch with commits GitHub does not have, or a tag pointing
#     elsewhere, is left alone and reported, unless MIRROR_FORCE=1, which makes
#     GitLab match GitHub exactly;
#   - refs only on GitLab are never touched; a ref is deleted on GitLab only
#     when it was deleted on GitHub.
#
# env: SOURCE_URL (GitHub repo), TARGET_URL (GitLab repo), GITLAB_TOKEN (for https),
#      MIRROR_FORCE=1 (optional)
set -euo pipefail

mode=${1:?usage: mirror-to-gitlab.sh all|push <ref>|delete <ref>}
ref=${2:-}
: "${SOURCE_URL:?}" "${TARGET_URL:?}"
FORCE=${MIRROR_FORCE:-0}
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
      echo "GitLab refused a protected branch. Give the token the Maintainer role; to overwrite a" >&2
      echo "diverged protected branch, also allow force push on it (Settings > Repository >" >&2
      echo "Protected branches)." >&2
    fi
    return 1
  fi
  cat "$work/push.err"
}

if [ "$mode" = delete ]; then
  if git ls-remote --exit-code "$TARGET_URL" "$ref" >/dev/null 2>&1; then
    echo ">>> deleting ${ref} on GitLab (deleted on GitHub)"
    push ":${ref}"
  else
    echo ">>> ${ref} is not on GitLab; nothing to delete"
  fi
  exit 0
fi

# GitHub's refs under refs/heads + refs/tags, GitLab's under refs/gitlab/...
if [ "$mode" = all ]; then
  git fetch -q --prune "$SOURCE_URL" '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
  git fetch -q "$TARGET_URL" '+refs/heads/*:refs/gitlab/heads/*' '+refs/tags/*:refs/gitlab/tags/*'
  refs=$(git for-each-ref --format='%(refname)' refs/heads refs/tags)
else
  git fetch -q "$SOURCE_URL" "+${ref}:${ref}"
  git fetch -q "$TARGET_URL" "+${ref}:refs/gitlab/${ref#refs/}" 2>/dev/null || true
  refs=$ref
fi

specs=(); skipped=(); n_new=0; n_ff=0; n_same=0; n_forced=0
for r in $refs; do
  gh=$(git rev-parse "$r")
  gl=$(git rev-parse -q --verify "refs/gitlab/${r#refs/}" || true)
  if [ -z "$gl" ]; then
    specs+=("${r}:${r}"); n_new=$((n_new + 1))
  elif [ "$gl" = "$gh" ]; then
    n_same=$((n_same + 1))
  elif [[ "$r" == refs/heads/* ]] && git merge-base --is-ancestor "$gl" "$gh"; then
    specs+=("${r}:${r}"); n_ff=$((n_ff + 1))
  elif [ "$FORCE" = 1 ]; then
    specs+=("+${r}:${r}"); n_forced=$((n_forced + 1))
  else
    skipped+=("${r#refs/}: GitLab ${gl:0:9}, GitHub ${gh:0:9}")
  fi
done

echo ">>> ${n_new} new, ${n_ff} fast-forward, ${n_forced} forced, ${n_same} already equal, ${#skipped[@]} left alone"
status=0
if [ ${#specs[@]} -gt 0 ]; then
  push "${specs[@]}" || status=1
fi
if [ ${#skipped[@]} -gt 0 ]; then
  echo "These GitLab refs have commits GitHub does not have (or point elsewhere), so they were not overwritten:"
  printf '  %s\n' "${skipped[@]}"
  echo "::warning::${#skipped[@]} GitLab ref(s) differ from GitHub and were left alone (see the log). Run the 'GitLab mirror' workflow with 'force' ticked to make GitLab match GitHub."
fi
exit $status
