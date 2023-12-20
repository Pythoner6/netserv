get_chart_name() {
  manifest="$1/blobs/$(jq -r '.manifests[0].digest | sub(":";"/")' "$1/index.json")"
  config="$1/blobs/$(jq -r '.config.digest | sub(":";"/")' "$manifest")"
  jq -r '.name' "$config"
}

get_chart_version() {
  digest="$(jq -r '.manifests[0].digest | sub(":"; ".")' "$1/index.json")"
  manifest="$1/blobs/$(jq -r '.manifests[0].digest | sub(":";"/")' "$1/index.json")"
  config="$1/blobs/$(jq -r '.config.digest | sub(":";"/")' "$manifest")"
  version="$(jq -r '.version' "$config")"
  name="$(jq -r '.name' "$config")"
  echo "${version#v}+$digest"
}

get_chart_digest() {
  jq -r '.manifests[0].digest | sub("^[^:]*:"; "")' "$1/index.json"
}

get_chart_digest_type() {
  jq -r '.manifests[0].digest | sub(":.*$"; "")' "$1/index.json"
}
