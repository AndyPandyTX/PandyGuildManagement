#!/usr/bin/env bash
# Posts a release to Discord through a webhook (DISCORD_WEBHOOK).
#   announce.sh v0.12.0
# The notes are, in order: ANNOUNCE_NOTES if set, an annotated tag's message,
# or the commit subjects since the tag before (version bumps left out).
set -euo pipefail
tag="$1"
git fetch --force --tags --quiet

notes="${ANNOUNCE_NOTES:-}"
if [ -z "${notes//[[:space:]]/}" ] && [ "$(git cat-file -t "$tag")" = "tag" ]; then
  notes=$(git tag -l --format='%(contents)' "$tag" | sed '/-----BEGIN PGP/,$d')
fi
if [ -z "${notes//[[:space:]]/}" ]; then
  prev=$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null || true)
  notes=$(git log --no-merges --format='- %s' ${prev:+"$prev.."}"$tag" | grep -vE '^- v[0-9]+(\.[0-9]+)+$' || true)
fi

url="https://github.com/$GITHUB_REPOSITORY/releases/tag/$tag"
jq -n --arg title "Pandy Guild & Groups $tag is out" --arg url "$url" --arg notes "${notes:0:3800}" '{
  username: "PandyBot",
  embeds: [{
    title: $title,
    url: $url,
    color: 5558676,
    description: $notes,
    footer: { text: "Update with the CurseForge app, or download from CurseForge, Wago or GitHub." }
  }]
}' | curl -fsS -H "Content-Type: application/json" -d @- "$DISCORD_WEBHOOK"
echo "Announced $tag on Discord."
