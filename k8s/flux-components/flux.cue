package netserv

import (
  "encoding/yaml"
  kustomization "kustomize.toolkit.fluxcd.io/kustomization/v1"
  ocirepository "source.toolkit.fluxcd.io/ocirepository/v1beta2"
  helmrepository "source.toolkit.fluxcd.io/helmrepository/v1beta2"
)

appName: "flux"

kustomizations: components: {
  _extraManifests: yaml.Unmarshal(extraManifests)
}

fluxResources: {
  oci: ocirepository.#OCIRepository & {
    #Repository
    spec: {
      interval: "1m0s"
      ref: tag: "latest"
      url: "oci://ghcr.io/pythoner6/netserv"
    }
  }
  helm: helmrepository.#HelmRepository & {
    #HelmRepository
    spec: {
      type: "oci"
      url: "oci://ghcr.io/pythoner6/charts"
    }
  }
  "root": kustomization.#Kustomization & {
    spec: {
      path: "./"
      interval: "10m0s"
      prune: true
      sourceRef: #Ref & {_obj: #Repository}
    }
  }
}
