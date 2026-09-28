#!/usr/bin/env bash
# Print every image reference in rendered manifests, one per line, deduped.
# Catches plain `image:` / `imageName:` strings and `image: {registry, repository, tag|digest}` maps.
set -euo pipefail
yq -o=json -N '.' "$@" 2>/dev/null | jq -r '
  .. | objects | to_entries[]
  | select(.key == "image" or .key == "imageName" or .key == "containerImage")
  | .value
  | if type == "string" then .
    elif type == "object" and (.repository // "") != "" then
      ((.registry // "") | if . == "" then "" else . + "/" end)
      + .repository
      + (if (.digest // "") != "" then "@" + .digest
         elif (.tag // "") != "" then ":" + (.tag | tostring)
         else "" end)
    else empty end' | grep -vE '^\s*$|\{\{' | sort -u
