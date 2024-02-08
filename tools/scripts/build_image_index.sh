set -euxo pipefail
declare -A imageArtifacts="($(jq -r 'to_entries | map([.key, .value][]) | @sh' <<< "$(cat)"))"
images=""
for name in "${!imageArtifacts[@]}"; do
  digest="$(jq -r '.manifests[0].digest' "${imageArtifacts[$name]}/index.json")"
  images+="$(jq -n --arg name "$name" --arg digest "$digest" '{$name: $digest}')"
done
jq -s 'reduce .[] as $image ({}; . * $image)' <<< "$images" > "$out"
set +x
