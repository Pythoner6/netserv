set -euxo pipefail
# Read input json
declare -A input="($(jq -r 'to_entries | map(.key, .value | tostring) | @sh' <<< "$(cat)"))"
declare -a cueDefinitions="($(jq -r '@sh' <<< "${input[cueDefinitions]}"))"
# Symlink in the generated cue definitions
mkdir -p cue.mod/gen/ "$out"
declare -p input
declare -p cueDefinitions
readarray -t cueDefinitions <<< "$(find "${cueDefinitions[@]}" -maxdepth 1 -mindepth 1 -type d)"
ln -s "${cueDefinitions[@]}" cue.mod/gen/
ls cue.mod/gen/
# Run cue
mkdir -p "$out"
package="${input[path]}:${input[cuePackageName]}"
declare -a args=(
  --inject "charts=$(cat "${input[chartIndex]}")"
)
if [[ "${input[extraManifests]}" != "null" ]]; then
  args+=(--inject "extraManifests=${input[extraManifests]}")
fi
cue vet -v -c "${args[@]}" "./$package"
args+=(--inject "outputDir=$out")
cue cmd -v "${args[@]}" synth "./$package"
set +x
