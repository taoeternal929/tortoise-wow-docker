#!/usr/bin/env bash
# Keep a GitLab branch at "upstream branch + server/patches/*.patch".
#
# The tree is upstream at UPSTREAM_COMMIT with the patches applied, the same
# thing server/Dockerfile compiles. It is written as one commit on top of the
# GitLab branch, with the upstream commit as a second parent, so the GitLab
# history looks like "merge upstream into <branch>" and the push is always a
# fast-forward (never a force push).
#
# Two workflows call this: upstream-sync.yml after each build (with BUILD_TAG,
# which tags the exact source of an image) and gitlab-mirror.yml every hour to
# follow upstream's branches (no tag). Each commit records the upstream commit
# it stands for, so the branch never moves backwards: backing up an older build
# than the branch already holds only adds the tag.
#
# Required env: GITLAB_REPO_URL GITLAB_BRANCH UPSTREAM_REPO UPSTREAM_BRANCH
#               UPSTREAM_COMMIT PATCH_DIR
# Optional env: BUILD_TAG (tag to create), GITLAB_TOKEN (needed for https pushes),
#               DRY_RUN=1 (no push), SOURCE_NOTE (extra line for the commit message)
set -euo pipefail

for v in GITLAB_REPO_URL GITLAB_BRANCH UPSTREAM_REPO UPSTREAM_BRANCH UPSTREAM_COMMIT PATCH_DIR; do
  [ -n "${!v:-}" ] || { echo "missing env: $v" >&2; exit 2; }
done
PATCH_DIR=$(cd "$PATCH_DIR" && pwd)
DRY_RUN=${DRY_RUN:-0}
BUILD_TAG=${BUILD_TAG:-}

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
patch_lines() {
  if [ ${#patches[@]} -eq 0 ]; then echo "Patches:  none"; return; fi
  echo "Patches:"
  for p in "${patches[@]}"; do echo "  ${p##*/}  sha256:$(sha256sum "$p" | cut -c1-16)"; done
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q "$work"
cd "$work"
git config user.name  "tortoise-wow-docker CI"
git config user.email "ci@tortoise-wow-docker.invalid"
if [ -n "${GITLAB_TOKEN:-}" ]; then
  # Hand the token to git through a credential helper so it never appears in a
  # URL, the process list or the log, and only for the GitLab host (never for
  # the upstream fetch from GitHub).
  gitlab_origin=$(printf '%s' "$GITLAB_REPO_URL" | sed -E 's#^(https?://[^/]+).*#\1#')
  git config "credential.${gitlab_origin}.helper" '!f() { echo username=oauth2; echo "password=${GITLAB_TOKEN}"; }; f'
fi
git remote add gitlab   "$GITLAB_REPO_URL"
git remote add upstream "$UPSTREAM_REPO"

push() {  # push with a readable explanation of GitLab's protected-branch refusal
  if [ "$DRY_RUN" = 1 ]; then echo ">>> DRY_RUN: would push $*"; return 0; fi
  if ! git push "$@" 2> "$work/push.err"; then
    cat "$work/push.err" >&2
    if grep -qiE 'protected branch|not allowed to (push|force)' "$work/push.err"; then
      echo "GitLab refused the push to protected branch ${GITLAB_BRANCH}. Give the token the Maintainer" >&2
      echo "role, or allow Developers to push to ${GITLAB_BRANCH} (Settings > Repository > Protected branches)." >&2
    fi
    return 1
  fi
  cat "$work/push.err"
}
tag_exists() { [ -n "$BUILD_TAG" ] && git ls-remote --exit-code --tags gitlab "refs/tags/${BUILD_TAG}" >/dev/null 2>&1; }
# Upstream commit a GitLab commit stands for (from its "Upstream:" line; empty if none).
upstream_of() { git log -1 --format=%B "$1" | awk '/^Upstream: / { print $3; exit }'; }

echo ">>> GitLab ${GITLAB_BRANCH} <- upstream ${UPSTREAM_BRANCH} ${UPSTREAM_COMMIT:0:12}${BUILD_TAG:+ (tag ${BUILD_TAG})}"

# Cheap check first: when the branch already stands for this upstream commit
# with the same patches (and the tag, if any, exists), there is nothing to do.
head=""
if git fetch -q --no-tags --depth 1 gitlab "+refs/heads/${GITLAB_BRANCH}:refs/remotes/gitlab/${GITLAB_BRANCH}" 2>/dev/null; then
  head=$(git rev-parse "refs/remotes/gitlab/${GITLAB_BRANCH}")
  if [ "$(upstream_of "$head")" = "$UPSTREAM_COMMIT" ] \
     && diff -q <(git log -1 --format=%B "$head" | sed -n '/^Patch/,/^[^ P]/p' | grep -E '^(Patches|  )') <(patch_lines) >/dev/null; then
    if [ -z "$BUILD_TAG" ] || tag_exists; then
      echo "    already up to date (${head:0:12})"
      exit 0
    fi
    push -q gitlab "${head}:refs/tags/${BUILD_TAG}"
    echo "    already up to date; tagged ${head:0:12} as ${BUILD_TAG}"
    exit 0
  fi
else
  echo "    branch ${GITLAB_BRANCH} not found on GitLab; it will be created"
fi

echo ">>> fetching full history (GitLab ${GITLAB_BRANCH}, upstream ${UPSTREAM_BRANCH})"
if [ -n "$head" ]; then
  git fetch -q --unshallow --no-tags gitlab "+refs/heads/${GITLAB_BRANCH}:refs/remotes/gitlab/${GITLAB_BRANCH}"
fi
git fetch -q --no-tags upstream "+refs/heads/${UPSTREAM_BRANCH}:refs/remotes/upstream/${UPSTREAM_BRANCH}"
if ! git cat-file -e "${UPSTREAM_COMMIT}^{commit}" 2>/dev/null; then
  git fetch -q --no-tags upstream "${UPSTREAM_COMMIT}"
fi

echo ">>> building the patched tree"
export GIT_INDEX_FILE="$work/.git/backup-index"
git read-tree "${UPSTREAM_COMMIT}"
for p in "${patches[@]}"; do
  echo "    applying ${p##*/}"
  if ! git apply --cached --whitespace=nowarn "$p"; then
    echo "${p##*/} does not apply to upstream ${UPSTREAM_BRANCH} ${UPSTREAM_COMMIT:0:12}; see server/patches/README.md" >&2
    exit 1
  fi
done
tree=$(git write-tree)
unset GIT_INDEX_FILE

message() {
  echo "Merge upstream ${UPSTREAM_BRANCH} ${UPSTREAM_COMMIT:0:12} with tortoise-wow-docker patches"
  echo
  echo "Upstream: ${UPSTREAM_REPO} ${UPSTREAM_COMMIT}"
  if [ -n "$BUILD_TAG" ]; then echo "Build:    ${BUILD_TAG}"; fi
  patch_lines
  if [ -n "${SOURCE_NOTE:-}" ]; then echo "${SOURCE_NOTE}"; fi
}

head_up=""
[ -n "$head" ] && head_up=$(upstream_of "$head")

# Case 1: the branch already holds exactly this tree.
if [ -n "$head" ] && [ "$(git rev-parse "${head}^{tree}")" = "$tree" ]; then
  echo ">>> GitLab ${GITLAB_BRANCH} already holds this exact tree"
  if [ -n "$BUILD_TAG" ] && ! tag_exists; then push -q gitlab "${head}:refs/tags/${BUILD_TAG}"; echo "    tagged ${head:0:12} as ${BUILD_TAG}"; fi
  exit 0
fi

# Case 2: the branch already stands for a newer upstream commit (e.g. the hourly
# follower ran before this build's backup). Keep the branch; the tag alone
# records the built source, on a commit whose parent is the upstream commit.
if [ -n "$head_up" ] && [ "$head_up" != "$UPSTREAM_COMMIT" ] \
   && git cat-file -e "${head_up}^{commit}" 2>/dev/null \
   && git merge-base --is-ancestor "$UPSTREAM_COMMIT" "$head_up"; then
  echo ">>> GitLab ${GITLAB_BRANCH} is already at newer upstream ${head_up:0:12}; not moving it back"
  if [ -n "$BUILD_TAG" ]; then
    if tag_exists; then echo "    tag ${BUILD_TAG} already exists"; exit 0; fi
    side=$(message | git commit-tree "$tree" -p "$UPSTREAM_COMMIT")
    push -q gitlab "${side}:refs/tags/${BUILD_TAG}"
    echo "    tagged ${side:0:12} (off-branch) as ${BUILD_TAG}"
  fi
  exit 0
fi

# Case 3: move the branch forward.
parents=()
[ -n "$head" ] && parents+=(-p "$head")
if [ -z "$head" ] || ! git merge-base --is-ancestor "${UPSTREAM_COMMIT}" "$head"; then
  parents+=(-p "${UPSTREAM_COMMIT}")
fi
commit=$(message | git commit-tree "$tree" "${parents[@]}")
echo ">>> new commit ${commit}"
message | sed 's/^/    /'
if [ -n "$head" ]; then
  echo "    files changed vs GitLab ${GITLAB_BRANCH}: $(git diff --name-only "$head" "$commit" | wc -l)"
fi

refs=("${commit}:refs/heads/${GITLAB_BRANCH}")
if [ -n "$BUILD_TAG" ]; then
  if tag_exists; then
    echo "tag ${BUILD_TAG} already exists on GitLab but points at a different tree; refusing to move it" >&2
    exit 1
  fi
  refs+=("${commit}:refs/tags/${BUILD_TAG}")
fi
push --atomic gitlab "${refs[@]}"
echo ">>> pushed ${commit:0:12} to GitLab ${GITLAB_BRANCH}${BUILD_TAG:+ and tagged ${BUILD_TAG}}"
