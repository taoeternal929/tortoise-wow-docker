#!/usr/bin/env bash
# Bring this repo in line with an upstream commit and write a PR description.
#
#   sync-upstream.sh <upstream checkout dir> <new commit> <new image tag> <report.md>
#
# Run from the repo root. It:
#   - mirrors upstream sql/database_updates/<db>/*.sql into data/database_updates/<db>/
#   - sorts the changes into new / edited / removed migrations
#   - lists config keys that differ between upstream's *.conf.dist.in and ours
#   - updates the pinned commit (server/upstream.env) and image tag (docker-compose.yml)
#   - writes a Markdown report for the pull request body
set -euo pipefail

up=$(cd "$1" && pwd); new_commit=$2; new_tag=$3; report=$4
# shellcheck disable=SC1091
. server/upstream.env
old_commit=$UPSTREAM_COMMIT
repo_web=${UPSTREAM_REPO%.git}

new=(); edited=(); removed=()
for db in world character auth; do
  src="$up/sql/database_updates/$db"; dst="data/database_updates/$db"
  mkdir -p "$dst"
  if [ -d "$src" ]; then
    for f in "$src"/*.sql; do
      [ -e "$f" ] || continue
      name=${f##*/}
      if [ ! -e "$dst/$name" ]; then new+=("$db/$name")
      elif ! cmp -s "$f" "$dst/$name"; then edited+=("$db/$name"); fi
      cp "$f" "$dst/$name"
    done
  fi
  for f in "$dst"/*.sql; do
    [ -e "$f" ] || continue
    [ -e "$src/${f##*/}" ] || { removed+=("$db/${f##*/}"); rm "$f"; }
  done
  # git cannot store an empty folder, and mangosd aborts at startup if a
  # configured update folder is missing on its read-only mount.
  [ -n "$(ls -A "$dst")" ] || touch "$dst/.gitkeep"
done

conf_keys() { grep -oE '^[[:space:]]*[A-Za-z][A-Za-z0-9_.]*[[:space:]]*=' "$1" | sed -E 's/[[:space:]]*=$//; s/^[[:space:]]+//' | sort -u; }
conf_report() {  # <ours> <upstream dist>
  local ours=$1 dist=$2 added gone
  [ -f "$dist" ] || { echo "- \`$ours\`: upstream template not found, skipped"; return; }
  added=$(comm -13 <(conf_keys "$ours") <(conf_keys "$dist") | sed 's/.*/`&`/' | paste -sd ' ' -)
  gone=$(comm -23 <(conf_keys "$ours") <(conf_keys "$dist") | sed 's/.*/`&`/' | paste -sd ' ' -)
  echo "- \`$ours\`"
  echo "  - in upstream's template but not ours: ${added:-none}"
  echo "  - ours but no longer in upstream's template: ${gone:-none}"
}

sed -i -E "s|^UPSTREAM_COMMIT=.*|UPSTREAM_COMMIT=${new_commit}|" server/upstream.env
sed -i -E "s|(TW_IMAGE_TAG:-)[^}]*|\1${new_tag}|g; s|(UPSTREAM_COMMIT: )[0-9a-f]{40}|\1${new_commit}|g" docker-compose.yml

list() { if [ $# -eq 0 ]; then echo "_none_"; else printf -- '- `%s`\n' "$@"; fi; }
{
  echo "Automated sync of upstream \`${UPSTREAM_BRANCH}\` to [\`${new_commit:0:7}\`](${repo_web}/commit/${new_commit})."
  echo
  if [ "$old_commit" != "$new_commit" ]; then
    echo "Upstream changes: [\`${old_commit:0:7}...${new_commit:0:7}\`](${repo_web}/compare/${old_commit}...${new_commit})"
  else
    echo "Same upstream commit as before; the build files in server/ changed."
  fi
  echo
  echo "**Images** (already built and pushed):"
  echo "- \`tortoise-wow-realmd:${new_tag}\`"
  echo "- \`tortoise-wow-mangosd:${new_tag}\`"
  echo "- \`tortoise-wow-tools:${new_tag}\`"
  echo
  echo "To deploy after merging: \`git pull && docker compose pull realmd mangosd && docker compose up -d\`"
  echo
  if [ ${#edited[@]} -gt 0 ]; then
    echo "### ⚠️ Edited migrations (${#edited[@]})"
    echo
    echo "Upstream changed these after they were released. mangosd identifies migrations by file hash, so"
    echo "**servers that already applied the old version will run the whole file again** on next start."
    echo "Files that insert rows with fixed IDs fail the second time, and mangosd then waits at startup."
    echo "For each one, either check it is safe to re-run, or mark the new hash as applied on existing servers."
    echo
    list "${edited[@]}"
    echo
  fi
  echo "### New migrations (${#new[@]})"
  echo
  list "${new[@]}"
  echo
  if [ ${#removed[@]} -gt 0 ]; then
    echo "### Removed upstream (${#removed[@]})"
    echo
    list "${removed[@]}"
    echo
  fi
  echo "### Config settings to review"
  echo
  conf_report mangosd/mangosd.conf "$up/src/mangosd/mangosd.conf.dist.in"
  conf_report realmd/realmd.conf "$up/src/realmd/realmd.conf.dist.in"
} > "$report"

echo "new=${#new[@]} edited=${#edited[@]} removed=${#removed[@]}"
