#!/usr/bin/env bash
# Scan each image in a list with Trivy and emit one JSON summary line per image.
# Usage: scan-images.sh <images.txt> <out-dir> [severity] [ignore-unfixed]
set -uo pipefail
LIST=$1; OUT=$2; SEVERITY=${3:-CRITICAL,HIGH}; IGNORE_UNFIXED=${4:-true}
mkdir -p "$OUT/json"
: > "$OUT/summary.jsonl"

UNFIXED_FLAG=""; [ "$IGNORE_UNFIXED" = "true" ] && UNFIXED_FLAG="--ignore-unfixed"

while IFS= read -r img; do
  [ -z "$img" ] && continue
  f="$OUT/json/$(echo "$img" | tr '/:@' '___').json"
  if trivy image --scanners vuln --pkg-types os,library --severity "$SEVERITY" $UNFIXED_FLAG \
       --format json --output "$f" --timeout 10m --quiet "$img" 2> "$f.err"; then
    jq -c --arg img "$img" '
      [.Results[]?.Vulnerabilities[]?] as $v
      | {image: $img, status: "ok",
         critical: ($v | map(select(.Severity=="CRITICAL")) | length),
         high:     ($v | map(select(.Severity=="HIGH")) | length),
         total:    ($v | length),
         cves:     ($v | map(.VulnerabilityID) | unique)}' "$f" >> "$OUT/summary.jsonl"
  else
    jq -nc --arg img "$img" --arg err "$(grep -v '^\s*$' "$f.err" | tail -1 | sed 's/^[[:space:]]*\*[[:space:]]*//' | cut -c1-200)" \
      '{image: $img, status: "error", critical: 0, high: 0, total: 0, cves: [], error: $err}' >> "$OUT/summary.jsonl"
  fi
done < "$LIST"

jq -s '{scanned: length, ok: map(select(.status=="ok")) | length, errors: map(select(.status=="error")) | length,
        critical: map(.critical) | add, high: map(.high) | add, total: map(.total) | add}' "$OUT/summary.jsonl"
