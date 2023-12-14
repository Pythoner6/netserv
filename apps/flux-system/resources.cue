package resources

import (
  ocirepository "source.toolkit.fluxcd.io/ocirepository/v1beta2"
  kustomization "kustomize.toolkit.fluxcd.io/kustomization/v1"
)

#Namespace: {_name: "flux-system"}
#Resources: {
  ghcr="netserv-ghcr": ocirepository.#OCIRepository & {
    spec: {
      interval: "1m0s"
      ref: tag: "latest"
      url: "oci://ghcr.io/pythoner6/netserv"
    }
  }
  netserv: kustomization.#Kustomization & {
    spec: {
      path: "./"
      interval: "10m0s"
      prune: true
      sourceRef: #Ref & {_obj: ghcr}
    }
  }
}
