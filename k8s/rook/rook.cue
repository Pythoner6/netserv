package netserv

import (
  "pythoner6.dev/c8s"
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

appName: "rook"
#Charts: _

let namespace = c8s.#Namespace & {
  #name: "rook-system"
  metadata: labels: {
    "pod-security.kubernetes.io/enforce": "privileged"
    "pod-security.kubernetes.io/audit": "privileged"
    "pod-security.kubernetes.io/warn": "privileged"
  }
}

kustomizations: helm: #defaultResourceNamespace: namespace
kustomizations: helm: "release": {
  ns: namespace
  (appName): helmrelease.#HelmRelease & {
    spec: {
      chart: spec: #Charts["rook-ceph"]
      interval: "10m0s"
    }
  }
}

//kustomizations: cluster: #dependsOn: [kustomizations.helm]
//kustomizations: cluster: "manifest": {
//}

//kustomizations: objectstore: #dependsOn: [kustomizations.helm]
//kustomizations: objectstore: "manifest": {
//}
