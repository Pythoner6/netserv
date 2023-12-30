package netserv

import (
  "encoding/yaml"
  ocirepository "source.toolkit.fluxcd.io/ocirepository/v1beta2"
  cilium "pythoner6.dev/netserv/k8s/cilium:netserv"
  es "pythoner6.dev/netserv/k8s/external-secrets:netserv"
  flux "pythoner6.dev/netserv/k8s/flux-components:netserv"
  cm "pythoner6.dev/netserv/k8s/cert-manager:netserv"
)

appName: "root"

#apps: [
  flux,
  cilium,
  es,
  cm,
]

#digests: yaml.Unmarshal({s: string @tag(digests)}.s)

kustomizations: $default: "flux-resources": {
  #namespace: #FluxNamespace
  for app in #apps for _, resource in app.#fluxResources {
    "\(resource.kind):\(resource.metadata.namespace):\(resource.metadata.name)": [
      if resource.kind == ocirepository.#OCIRepository.kind {
        resource & {spec: ref: digest: #digests[resource.metadata.name]}
      },
      resource
    ][0]
  }
  for _, resource in #fluxResources {
    "\(resource.kind):\(resource.metadata.namespace):\(resource.metadata.name)": resource
  }
}
