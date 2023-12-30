package netserv

import (
  dcsi "pythoner6.dev/netserv/k8s/democratic-csi:netserv"
  cnpg "pythoner6.dev/netserv/k8s/cnpg:netserv"
  clusters "postgresql.cnpg.io/cluster/v1"
)

appName: "gitlab"
#Charts: _

kustomizations: $default: #dependsOn: [dcsi.kustomizations.helm, cnpg.kustomizations.helm]
kustomizations: $default: manifest: {
  ns: #AppNamespace
  cluster: clusters.#Cluster & {
    metadata: name: "gitlab"
    spec: {
      instances: 3
      maxSyncReplicas: 2
      minSyncReplicas: 2
      storage: {
        storageClass: dcsi.localHostpath
        size: "10Gi"
      }
      affinity: nodeAffinity: requiredDuringSchedulingIgnoredDuringExecution: nodeSelectorTerms: [{
        matchExpressions: [{
          key: "storage"
          operator: "In"
          values: ["yes"]
        }]
      }]
    }
  }
  cluster: clusters.#Cluster & {
    metadata: name: "praefect"
    spec: {
      instances: 3
      maxSyncReplicas: 2
      minSyncReplicas: 2
      storage: {
        storageClass: dcsi.localHostpath
        size: "1Gi"
      }
      affinity: nodeAffinity: requiredDuringSchedulingIgnoredDuringExecution: nodeSelectorTerms: [{
        matchExpressions: [{
          key: "storage"
          operator: "In"
          values: ["yes"]
        }]
      }]
    }
  }
}

//kustomizations: helm: #dependsOn: [kustomizations["$default"]]
//kustomizations: helm: manifest: {
//}
