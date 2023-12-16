echo "$TOKEN" | helm registry login "$REGISTRY" -u "$ACTOR" --pasword-stdin
find result/ -name '*.tgz' -execdir helm push "{}" "oci://$REGISTRY" \;
