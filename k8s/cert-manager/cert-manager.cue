package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
  clusterissuer "cert-manager.io/clusterissuer/v1"
)

appName: "cert-manager"

kustomizations: {
  helm: "release": {
    ns: #AppNamespace & {
      metadata: labels: {
        "pod-security.kubernetes.io/enforce": "privileged"
        "pod-security.kubernetes.io/audit": "privileged"
        "pod-security.kubernetes.io/warn": "privileged"
      }
    }
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
    "letsencrypt": this=(clusterissuer.#ClusterIssuer & {
      spec: acme: {
        email: "joseph@josephmartin.org"
        server: "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef: {
          name: "\(this.metadata.name)-key"
        }
        solvers: [{
          dns01: digitalocean: tokenSecretRef: { name: "digitalocean-token", key: "access-token" }
        }]
      }
    })
  }
}

