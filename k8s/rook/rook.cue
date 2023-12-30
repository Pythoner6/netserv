package netserv

import (
  "pythoner6.dev/c8s"
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
  clusters "ceph.rook.io/cephcluster/v1"
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

kustomizations: cluster: #dependsOn: [kustomizations.helm]
kustomizations: cluster: "manifest": {
  cluster: clusters.#CephCluster & {
    spec: {
      cephVersion: image: "quay.io/ceph/ceph:v18.2.1"
      dataDirHostPath: "/var/storage/rook",
      placement: all: nodeAffinity: requiredDuringSchedulingIgnoredDuringExecution: nodeSelectorTerms: [{
        matchExpressions: [{
          key: "ceph"
          operator: "In"
          values: ["yes"]
        }]
      }]
      mon: {
        count: 3
        allowMultiplePerNode: false
      }
      mgr: {
        count: 2
        allowMultiplePerNode: false
        modules: [
          {
            name: "pg_autoscaler"
            enabled: true
          },
          {
            name: "rook"
            enabled: true
          },
        ]
      }
      dashboard: {
        enabled: true
        ssl: false
      }
      monitoring: {
        enabled: false
        metricsDisabled: true
      }
      network: connections: {
        encryption: enabled: true
        compression: enabled: false
        requireMsgr2: true
      }
      storage: {
        useAllNodes: false
        useAllDevices: false
        nodes: [for node in ["talos-amb-yf5", "talos-egv-cns", "talos-n6u-n7u"] {
          name: node,
          devices: [{name: "/dev/nvme0n3"}],
        }]
      },
      disruptionManagement: managePodBudgets: true
    }
  }
}

//kustomizations: objectstore: #dependsOn: [kustomizations.helm]
//kustomizations: objectstore: "manifest": {
//}
