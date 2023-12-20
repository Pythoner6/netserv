package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
  kustomization "kustomize.toolkit.fluxcd.io/kustomization/v1"
  clusterissuer "cert-manager.io/clusterissuer/v1"
)

appName: "cert-manager"

// TODO: add "manifest groups" -> kustomizations, automate that
manifests: "../helmrelease.yaml": {
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

manifests: "issuers.yaml": {
  namespace: #AppNamespace
  clusterResources: "self-signed": clusterissuer.#ClusterIssuer & {
    spec: selfSigned: {}
  }
}

fluxResources: {
  chart="cert-manager-chart": kustomization.#Kustomization & {
    spec: {
      path: "./\(appName)/helmrelease.yaml"
      interval: "10m0s"
      prune: true
      sourceRef: #Ref & {_obj: #Repository}
    }
  }
  appKustomization: spec: dependsOn: [#DepRef & {_obj: chart}]
}
