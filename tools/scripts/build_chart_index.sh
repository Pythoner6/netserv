set -euxo pipefail
declare -a chartArtifacts="($(jq -r '@sh' <<< "$(cat)"))"
charts=""
for oci in "${chartArtifacts[@]}"; do
  declare -A chart="($(jq -r '.manifests[0].annotations | ["version", .["org.opencontainers.image.version"], "name", .["org.opencontainers.image.ref.name"]] | @sh' "$oci/index.json"))"
  charts+="$(jq -n --arg name "${chart[name]}" --arg version "${chart[version]#v}" '{$name: $version}')"
done
jq -s 'reduce .[] as $chart ({}; . * $chart)' <<< "$charts" > "$out"
set +x
