package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

appName: "external-secrets"

kustomizations: helm: "helmrelease.yaml": {
  clusterResources: ns: #AppNamespace
  resources: {
    (appName): helmrelease.#HelmRelease & {
      spec: {
        chart: spec: #Charts[appName]
        interval: "10m0s"
      }
    }
  }
}
