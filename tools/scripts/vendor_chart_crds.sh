values="$1"
kube_version="$2"

mkdir "$out"
mkdir cue.mod

helm template "$src" --include-crds --kube-version "$kube_version" --values <(echo "$values") | tee rendered.yaml >/dev/null

# Only process CRDs
yq -i 'select(.kind == "CustomResourceDefinition")' rendered.yaml
# This is an annoying workaround for a suspect definition in a crd from Rook https://github.com/rook/rook/issues/13414
# It _shouldn't_ affect other CRDs
yq -i 'with(select(.metadata.name == "objectbuckets.objectbucket.io").spec.versions[].schema.openAPIV3Schema.properties.spec.properties.authentication; del(.))' rendered.yaml

# Don't generate anything if there's no crds to process (timoni errors out)
if grep -q '[^[:space:]]' rendered.yaml; then
  timoni mod vendor crd -f rendered.yaml
  cp -a cue.mod/gen/. "$out"
fi
