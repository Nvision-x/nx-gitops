#!/usr/bin/env bash
# Render every layer chart of one environment the way ArgoCD/helm does and list the images it would run.
# Usage: render-env-images.sh <env-repo-checkout-dir> <out-dir>
set -euo pipefail
ENV_DIR=$1; OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT/rendered"

ENVF="$ENV_DIR/environment.yaml"
NAME=$(yq '.environment.name' "$ENVF")
PROFILE=$(yq '.environment.profile' "$ENVF")
REGISTRY=$(yq '.registry.url' "$ENVF")
DEFAULT_VERSION=$(yq '.registry.defaultVersion' "$ENVF")
LAYERS=$(yq '.deployment.layers[]' "$ENVF")

VALUES=(-f "$ENV_DIR/values.yaml")
[ -f "$ENV_DIR/profiles/$PROFILE.yaml" ] && VALUES+=(-f "$ENV_DIR/profiles/$PROFILE.yaml")

echo "env=$NAME profile=$PROFILE registry=$REGISTRY defaultVersion=$DEFAULT_VERSION"
: > "$OUT/layers.txt"
for layer in $LAYERS; do
  version=$(yq ".registry.chartVersions.$layer // \"$DEFAULT_VERSION\"" "$ENVF")
  tgz="$OUT/$layer-$version.tgz"
  [ -f "$tgz" ] || helm pull "oci://$REGISTRY/$layer" --version "$version" --destination "$OUT" >/dev/null
  if helm template "$layer" "$tgz" "${VALUES[@]}" > "$OUT/rendered/$layer.yaml" 2> "$OUT/rendered/$layer.err"; then
    echo "$layer $version ok" | tee -a "$OUT/layers.txt"
  else
    echo "$layer $version FAILED: $(head -c 300 "$OUT/rendered/$layer.err")" | tee -a "$OUT/layers.txt"
    rm -f "$OUT/rendered/$layer.yaml"
  fi
done

"$HERE/extract-images.sh" "$OUT"/rendered/*.yaml > "$OUT/images.txt"
echo "images=$(wc -l < "$OUT/images.txt")"
