package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

appName: "democratic-csi"
#Charts: _

kustomizations: helm: "release": {
  ns: #AppNamespace
  "local-path": helmrelease.#HelmRelease & {
    spec: {
      chart: spec: #Charts[appName]
      interval: "10m0s"
      values: {
      }
    }
  }
}
