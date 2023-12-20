set -euxo pipefail
config_media_type="application/vnd.cncf.helm.config.v1+json";
layer_media_type="application/vnd.cncf.helm.chart.content.v1.tar+gzip";
manifest_media_type="application/vnd.oci.image.manifest.v1+json";
annot_prefix="org.opencontainers.image";

mkdir -p $out/blobs/sha256
function sha() {
  sha256sum "$1" | cut -f1 -d' '
}
function len() {
  wc -c "$1" | cut -f1 -d' '
}

chartsha=$(sha "$src")
chartlen=$(len "$src")
cp "$src" "$out/blobs/sha256/$chartsha"

config="$(mktemp)"
helm show chart "$src" | yq -o json | jq --sort-keys -c > "$config"
configsha="$(sha "$config")"
configlen="$(len "$config")"
configcontent="$(cat "$config")"
cp "$config" "$out/blobs/sha256/$configsha"

manifest="$(mktemp)"
declare -a args
args=(
  --arg configsha "$configsha"
  --argjson configlen "$configlen"
  --arg chartsha "$chartsha"
  --argjson chartlen "$chartlen"
  --arg prefix "$annot_prefix"
  --arg config_media_type "$config_media_type"
  --arg layer_media_type "$layer_media_type"
)
jq --sort-keys -c "${args[@]}" "$(cat <<'EOF'
{
  schemaVersion: 2,
  config: {
    mediaType: $config_media_type,
    digest: ("sha256:"+$configsha),
    size: $configlen
  },
  layers: [{
    mediaType: $layer_media_type,
    digest: ("sha256:"+$chartsha),
    size: $chartlen
  }],
  annotations: {
    ($prefix+".authors"): (.maintainers // []) | map(.name + " (" + .email + ")") | join(", "),
    ($prefix+".description"): .description,
    ($prefix+".title"): .name,
    ($prefix+".url"): .home,
    ($prefix+".version"): .version
  }
}
EOF
)" "$config" > "$manifest"
manifestsha="$(sha "$manifest")"
manifestlen="$(len "$manifest")"
mv "$manifest" "$out/blobs/sha256/$manifestsha"

index="$(mktemp)"
version="$(jq -r '.version' "$config")"
name="$(jq -r '.name' "$config")"
args=(
  --arg manifestsha "$manifestsha"
  --argjson manifestlen "$manifestlen"
  --arg manifest_media_type "$manifest_media_type"
  --arg prefix "$annot_prefix"
  --arg version "${version#v}"
  --arg name "$name"
)
jq --sort-keys -n -c "${args[@]}" "$(cat <<'EOF'
{
  schemaVersion: 2,
  manifests: [{
    mediaType: $manifest_media_type,
    digest: ("sha256:" + $manifestsha),
    size: $manifestlen,
    annotations: {
      ($prefix+".version"): $version,
      ($prefix+".ref.name"): $name
    }
  }]
}
EOF
)" 2>&1 > "$index"
mv "$index" "$out/index.json"
echo '{"imageLayoutVersion":"1.0.0"}' > "$out/oci-layout"
set +x
