set -eo pipefail
echo "$TOKEN" | helm registry login "$REGISTRY" -u "$ACTOR" --password-stdin
find result/ -name '*.tgz' -execdir helm push "{}" "oci://$REGISTRY" \;
