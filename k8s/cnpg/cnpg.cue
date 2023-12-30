package netserv

import (
  "pythoner6.dev/c8s"
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

appName: "cnpg"
#Charts: _

let namespace = c8s.#Namespace & {#name: "cnpg-system"}

kustomizations: helm: #defaultResourceNamespace: namespace
kustomizations: helm: "release": {
  ns: namespace
  (appName): helmrelease.#HelmRelease & {
    spec: {
      chart: spec: #Charts["cloudnative-pg"]
      interval: "10m0s"
      values: {
      }
    }
  }
}
