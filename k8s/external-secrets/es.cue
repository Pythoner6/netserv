package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

appName: "external-secrets"
#Charts: _

kustomizations: helm: "release": {
  ns: #AppNamespace
  (appName): helmrelease.#HelmRelease & {
    spec: {
      chart: spec: #Charts[appName]
      interval: "10m0s"
    }
  }
}
