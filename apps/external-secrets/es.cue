package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

appName: "external-secrets"

manifests: "helmrelease.yaml": {
  namespace: #AppNamespace
  clusterResources: ns: namespace
  resources: {
    (appName): helmrelease.#HelmRelease & {
      spec: {
        chart: spec: #Charts[appName]
        interval: "10m0s"
      }
    }
  }
}
