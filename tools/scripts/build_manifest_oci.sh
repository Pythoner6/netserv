set -euxo pipefail
config_media_type="application/vnd.oci.image.config.v1+json";
layer_media_type="application/vnd.oci.image.layer.v1.tar+gzip";
manifest_media_type="application/vnd.oci.image.manifest.v1+json";

mkdir -p $out/blobs/sha256
function sha() {
  sha256sum "$1" | cut -f1 -d' '
}
function len() {
  wc -c "$1" | cut -f1 -d' '
}

declare -a input_dir_flags=()
if [[ ! -z "$1" ]]; then
  input_dir_flags+=("-C" "$1")
fi

layer_tar=$(mktemp)
layer_gz=$(mktemp)
tar_reproducible_flags=(
  --sort=name --mtime="@1"
  --owner=0 --group=0 --numeric-owner 
  --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime
)
mkdir -p "$out/blobs/sha256"
tar "${input_dir_flags[@]}" "${tar_reproducible_flags[@]}" -cf "$layer_tar" .
diffid="$(sha256sum "$layer_tar" | cut -f1 -d' ')"
gzip -c "$layer_tar" > "$layer_gz"
rm "$layer_tar"
layersha="$(sha "$layer_gz")"
layerlen="$(len "$layer_gz")"
mv "$layer_gz" "$out/blobs/sha256/$layersha"

config="$(mktemp)"
declare -a args
args=(
  --arg date "$(date -d "@1" -u "+%Y-%m-%dT%H:%M:%SZ")"
  --arg diffid "$diffid"
)
jq --sort-keys -n -c "${args[@]}" "$(cat <<'EOF'
{
  created: $date,
  architecture: "amd64",
  os: "linux",
  config: {},
  rootfs: {
    type: "layers",
    diff_ids: [ ("sha256:" + $diffid) ]
  }
}
EOF
)" > "$config"
configsha="$(sha "$config")"
configlen="$(len "$config")"
configcontent="$(cat "$config")"
mv "$config" "$out/blobs/sha256/$configsha"

manifest="$(mktemp)"
args=(
  --arg configsha "$configsha"
  --argjson configlen "$configlen"
  --arg layersha "$layersha"
  --argjson layerlen "$layerlen"
  --arg config_media_type "$config_media_type"
  --arg layer_media_type "$layer_media_type"
)
jq --sort-keys -n -c "${args[@]}" "$(cat <<'EOF'
{
  schemaVersion: 2,
  config: {
    mediaType: $config_media_type,
    digest: ("sha256:"+$configsha),
    size: $configlen
  },
  layers: [{
    mediaType: $layer_media_type,
    digest: ("sha256:"+$layersha),
    size: $layerlen
  }],
}
EOF
)" > "$manifest"
manifestsha="$(sha "$manifest")"
manifestlen="$(len "$manifest")"
mv "$manifest" "$out/blobs/sha256/$manifestsha"

index="$(mktemp)"
args=(
  --arg manifestsha "$manifestsha"
  --argjson manifestlen "$manifestlen"
  --arg manifest_media_type "$manifest_media_type"
)
jq --sort-keys -n -c "${args[@]}" "$(cat <<'EOF'
{
  schemaVersion: 2,
  manifests: [{
    mediaType: $manifest_media_type,
    digest: ("sha256:" + $manifestsha),
    size: $manifestlen
  }]
}
EOF
)" > "$index"
mv "$index" "$out/index.json"
echo '{"imageLayoutVersion":"1.0.0"}' > "$out/oci-layout"
set +x
