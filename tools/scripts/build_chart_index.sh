set -euxo pipefail
declare -a chartArtifacts="($(jq -r '@sh' <<< "$(cat)"))"
charts=""
for oci in "${chartArtifacts[@]}"; do
  digest="$(jq -r '.manifests[0].digest | sub("^[^:]*:"; "")' "$oci/index.json")"
  manifest="$oci/blobs/$(jq -r '.manifests[0].digest | sub(":";"/")' "$oci/index.json")"
  config="$oci/blobs/$(jq -r '.config.digest | sub(":";"/")' "$manifest")"
  name="$(jq -r '.name' "$config")"
  charts+="$(jq -n --arg name "$name" --arg digest "$digest" '{$name: $digest}')"
done
jq -s 'reduce .[] as $chart ({}; . * $chart)' <<< "$charts" > "$out"
set +x
