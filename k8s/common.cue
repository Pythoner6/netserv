package netserv

import (
  helmrepository "source.toolkit.fluxcd.io/helmrepository/v1beta2"
  "pythoner6.dev/c8s"
)

appName: string

#AppNamespace: c8s.#Namespace & {#name: appName}
#FluxNamespace: c8s.#Namespace & {#name: "flux-system"}

#ChartsRepo: helmrepository.#HelmRepository & {
  metadata: name: "netserv-ghcr"
  spec: {
    type: "oci"
    url: "oci://ghcr.io/pythoner6/charts"
  }
}

c8s.#Default & {
  #appName: appName
  #defaultKustomizationNamespace: #FluxNamespace
  #defaultResourceNamespace: #AppNamespace
  #repo: "ghcr.io/pythoner6/netserv"
  #charts: _ @tag(charts)
  #chartsRepo: #ChartsRepo
}

#Charts: c8s.#Charts
#fluxResources: c8s.#FluxResources
