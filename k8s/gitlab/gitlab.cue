package netserv

import (
  dcsi "pythoner6.dev/netserv/k8s/democratic-csi:netserv"
  cnpg "pythoner6.dev/netserv/k8s/cnpg:netserv"
  clusters "postgresql.cnpg.io/cluster/v1"
)

appName: "gitlab"
#Charts: _

kustomizations: $default: #dependsOn: [dcsi.kustomizations.helm, cnpg.kustomizations.helm]
kustomizations: $default: "manifest": {
  ns: #AppNamespace
  cluster: clusters.#Cluster & {
    metadata: name: "gitlab"
    spec: {
      instances: 3
      maxSyncReplicas: 3
      minSyncReplicas: 2
      storage: {
        storageClass: dcsi.localHostpath
        size: "10Gi"
      }
    }
  }
}
