package netserv

import (
  kustomization "kustomize.toolkit.fluxcd.io/kustomization/v1"
  ocirepository "source.toolkit.fluxcd.io/ocirepository/v1beta2"
)

fluxResources: {
  repository: ocirepository.#OCIRepository & {
    #Repository
    spec: {
      interval: "1m0s"
      ref: tag: "latest"
      url: "oci://ghcr.io/pythoner6/netserv"
    }
  }
  "root": kustomization.#Kustomization & {
    spec: {
      path: "./"
      interval: "10m0s"
      prune: true
      sourceRef: #Ref & {_obj: repository}
    }
  }
}
