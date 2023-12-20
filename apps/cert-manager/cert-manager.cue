package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
  //kustomization "kustomize.toolkit.fluxcd.io/kustomization/v1"
  clusterissuer "cert-manager.io/clusterissuer/v1"
)

appName: "cert-manager"

kustomizations: {
  helm: "manifest.yaml": {
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
  $default: _dependsOn: [helm]
  $default: "issuers.yaml": {
    namespace: #AppNamespace
    clusterResources: "self-signed": clusterissuer.#ClusterIssuer & {
      spec: selfSigned: {}
    }
  }
}

