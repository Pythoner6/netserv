package netserv

import (
  "strings"
  certmanager "pythoner6.dev/netserv/k8s/cert-manager:netserv"
  issuers "cert-manager.io/issuer/v1"
  certs "cert-manager.io/certificate/v1"
)

appName: "openldap"

kustomizations: {
  $default: #dependsOn: [certmanager.kustomizations["$default"]]
  $default: "manifest": {
    ldapCaCert="ldap-ca-cert": certs.#Certificate & {
      metadata: {}
      spec: {
        isCA: true
        literalSubject: "CN=ca,DC=ldap,DC=home,DC=josephmartin,DC=org"
        secretName: metadata.name
        privateKey: algorithm: "Ed25519"
        issuerRef: {
          name: certmanager.kustomizations["$default"].issuers["self-signed"].metadata.name
          kind: certmanager.kustomizations["$default"].issuers["self-signed"].kind
          group: strings.Split(certmanager.kustomizations["$default"].issuers["self-signed"].apiVersion, "/")[0]
        }
      }
    }
    "ldap-ca": issuers.#Issuer & {
      spec: ca: secretName: ldapCaCert.metadata.name
    }
  }
}

