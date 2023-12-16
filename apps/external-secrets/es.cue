package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

manifests: "helmrelease.yaml": {
  namespace: #Namespace & {_name: "external-secrets"}
  clusterResources: ns: namespace
  resources: {
    "external-secrets": helmrelease.#HelmRelease & {
      spec: {
        chart: spec: #Charts."external-secrets"
        interval: "10m0s"
      }
    }
  }
}
