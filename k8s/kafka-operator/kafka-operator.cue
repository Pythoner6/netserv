package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

appName: "kafka-operator"

kustomizations: helm: "release": {
  ns: #AppNamespace
  (appName): helmrelease.#HelmRelease & {
    spec: {
      chart: spec: #Charts["strimzi-kafka-operator"]
      interval: "10m0s"
      values: {
        watchNamespaces: ["gerrit"]
        featureGates: "+UseKRaft"
      }
    }
  }
}

