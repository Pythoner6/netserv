package resources

import (
  ocirepository "source.toolkit.fluxcd.io/ocirepository/v1beta2"
  kustomization "kustomize.toolkit.fluxcd.io/kustomization/v1"
)

#Namespace: {_name: "flux-system"}
#Resources: {
  netserv_ghcr: ocirepository.#OCIRepository & {
    metadata: name: "netserv-ghcr"
    spec: {
      interval: "1m0s"
      ref: tag: "latest"
      url: "oci://ghcr.io/pythoner6/netserv"
    }
  }
  ks: kustomization.#Kustomization & {
    metadata: name: "netserv"
    spec: {
      path: "./"
      interval: "10m0s"
      prune: true
      sourceRef: #Ref & {_obj: netserv_ghcr}
    }
  }
}
