package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
  clusterissuer "cert-manager.io/clusterissuer/v1"
)

appName: "cert-manager"

kustomizations: {
  helm: "release": {
    ns: #AppNamespace
    (appName): helmrelease.#HelmRelease & {
      spec: {
        chart: spec: #Charts[appName]
        interval: "10m0s"
        values: {
          installCRDs: true
          featureGates: "LiteralCertificateSubject=true"
          webhook: featureGates: "LiteralCertificateSubject=true"
        }
      }
    }
    "\(appName)-csi-driver": helmrelease.#HelmRelease & {
      spec: {
        chart: spec: #Charts["\(appName)-csi-driver"]
        interval: "10m0s"
      }
    }
  }
  $default: #dependsOn: [helm]
  $default: "issuers": {
    "self-signed": clusterissuer.#ClusterIssuer & {
      spec: selfSigned: {}
    }
  }
}

