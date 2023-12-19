get_chart_name() {
  manifest="$1/blobs/$(jq -r '.manifests[0].digest | sub(":";"/")' "$1/index.json")"
  config="$1/blobs/$(jq -r '.config.digest | sub(":";"/")' "$manifest")"
  jq -r '.name' "$config"
}

get_chart_digest() {
  jq -r '.manifests[0].digest | sub("^[^:]*:"; "")' "$1/index.json"
}

get_chart_digest_type() {
  jq -r '.manifests[0].digest | sub(":.*$"; "")' "$1/index.json"
}
