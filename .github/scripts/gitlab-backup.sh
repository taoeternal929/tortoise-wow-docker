#!/usr/bin/env bash
# Back up the exact source tree a build used to the GitLab repository.
#
# The tree is: upstream at UPSTREAM_COMMIT + server/patches/*.patch, the same
# thing server/Dockerfile compiles. It is written as one commit on top of the
# GitLab branch, with the upstream commit as a second parent, so the GitLab
# history keeps looking like "merge upstream into 1181dev" and the push is
# always a fast-forward (never a force push). A tag named BUILD_TAG marks the
# commit, matching the image tag in GHCR.
#
# Required env: GITLAB_REPO_URL GITLAB_BRANCH UPSTREAM_REPO UPSTREAM_BRANCH
#               UPSTREAM_COMMIT BUILD_TAG PATCH_DIR
# Optional env: GITLAB_TOKEN (needed for https pushes), DRY_RUN=1 (no push),
#               SOURCE_NOTE (extra line for the commit message)
set -euo pipefail

for v in GITLAB_REPO_URL GITLAB_BRANCH UPSTREAM_REPO UPSTREAM_BRANCH UPSTREAM_COMMIT BUILD_TAG PATCH_DIR; do
  [ -n "${!v:-}" ] || { echo "missing env: $v" >&2; exit 2; }
done
PATCH_DIR=$(cd "$PATCH_DIR" && pwd)
DRY_RUN=${DRY_RUN:-0}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q "$work"
cd "$work"
git config user.name  "tortoise-wow-docker CI"
git config user.email "ci@tortoise-wow-docker.invalid"
if [ -n "${GITLAB_TOKEN:-}" ]; then
  # Hand the token to git through a credential helper so it never appears in a
  # URL, the process list or the log.
  git config credential.helper '!f() { echo username=oauth2; echo "password=${GITLAB_TOKEN}"; }; f'
fi
git remote add gitlab   "$GITLAB_REPO_URL"
git remote add upstream "$UPSTREAM_REPO"

echo ">>> fetching GitLab ${GITLAB_BRANCH}"
head=""
if git fetch -q --no-tags gitlab "+refs/heads/${GITLAB_BRANCH}:refs/remotes/gitlab/${GITLAB_BRANCH}" 2>/dev/null; then
  head=$(git rev-parse "refs/remotes/gitlab/${GITLAB_BRANCH}")
  echo "    GitLab ${GITLAB_BRANCH} is at ${head}"
else
  echo "    branch ${GITLAB_BRANCH} not found on GitLab; it will be created"
fi

echo ">>> fetching upstream ${UPSTREAM_BRANCH}"
git fetch -q --no-tags upstream "+refs/heads/${UPSTREAM_BRANCH}:refs/remotes/upstream/${UPSTREAM_BRANCH}"
if ! git cat-file -e "${UPSTREAM_COMMIT}^{commit}" 2>/dev/null; then
  git fetch -q --no-tags upstream "${UPSTREAM_COMMIT}"
fi

echo ">>> building the patched tree"
export GIT_INDEX_FILE="$work/.git/backup-index"
git read-tree "${UPSTREAM_COMMIT}"
shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
for p in "${patches[@]}"; do
  echo "    applying ${p##*/}"
  git apply --cached --whitespace=nowarn "$p"
done
tree=$(git write-tree)
unset GIT_INDEX_FILE

tag_exists() { git ls-remote --exit-code --tags gitlab "refs/tags/${BUILD_TAG}" >/dev/null 2>&1; }

if [ -n "$head" ] && [ "$(git rev-parse "${head}^{tree}")" = "$tree" ]; then
  echo ">>> GitLab ${GITLAB_BRANCH} already holds this exact tree; nothing to commit"
  if tag_exists; then
    echo "    tag ${BUILD_TAG} already exists"
  elif [ "$DRY_RUN" = 1 ]; then
    echo "    DRY_RUN: would tag ${head} as ${BUILD_TAG}"
  else
    git push -q gitlab "${head}:refs/tags/${BUILD_TAG}"
    echo "    tagged ${head} as ${BUILD_TAG}"
  fi
  exit 0
fi

parents=()
[ -n "$head" ] && parents+=(-p "$head")
if [ -z "$head" ] || ! git merge-base --is-ancestor "${UPSTREAM_COMMIT}" "$head"; then
  parents+=(-p "${UPSTREAM_COMMIT}")
fi

{
  echo "Merge upstream ${UPSTREAM_BRANCH} ${UPSTREAM_COMMIT:0:12} with tortoise-wow-docker patches"
  echo
  echo "Upstream: ${UPSTREAM_REPO} ${UPSTREAM_COMMIT}"
  echo "Build:    ${BUILD_TAG}"
  if [ ${#patches[@]} -gt 0 ]; then
    echo "Patches:"
    for p in "${patches[@]}"; do echo "  ${p##*/}  sha256:$(sha256sum "$p" | cut -c1-16)"; done
  else
    echo "Patches:  none"
  fi
  if [ -n "${SOURCE_NOTE:-}" ]; then echo "${SOURCE_NOTE}"; fi
} > "$work/msg"
commit=$(git commit-tree "$tree" "${parents[@]}" -F "$work/msg")

echo ">>> new commit ${commit}"
cat "$work/msg" | sed 's/^/    /'
if [ -n "$head" ]; then
  echo "    files changed vs GitLab ${GITLAB_BRANCH}: $(git diff --name-only "$head" "$commit" | wc -l)"
fi

if tag_exists; then
  echo "tag ${BUILD_TAG} already exists on GitLab but points at a different tree; refusing to move it" >&2
  exit 1
fi

if [ "$DRY_RUN" = 1 ]; then
  echo ">>> DRY_RUN: not pushing"
  exit 0
fi
git push --atomic gitlab "${commit}:refs/heads/${GITLAB_BRANCH}" "${commit}:refs/tags/${BUILD_TAG}"
echo ">>> pushed ${commit} to GitLab ${GITLAB_BRANCH} and tagged ${BUILD_TAG}"
