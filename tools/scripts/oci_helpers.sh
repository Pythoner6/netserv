get_chart_name() {
  jq -r '.manifests[0].annotations["org.opencontainers.image.ref.name"]' "$1/index.json"
}

get_chart_version() {
  jq -r '.manifests[0].annotations["org.opencontainers.image.version"]' "$1/index.json"
}

get_chart_digest() {
  jq -r '.manifests[0].digest | sub("^[^:]*:"; "")' "$1/index.json"
}

get_chart_digest_type() {
  jq -r '.manifests[0].digest | sub(":.*$"; "")' "$1/index.json"
}
