package netserv

import (
  "pythoner6.dev/c8s"
  certmanager "pythoner6.dev/netserv/k8s/cert-manager:netserv"
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
  clusters "ceph.rook.io/cephcluster/v1"
  objectstores "ceph.rook.io/cephobjectstore/v1"
  storagev1 "k8s.io/api/storage/v1"
  certificates "cert-manager.io/certificate/v1"
  gateways "gateway.networking.k8s.io/gateway/v1"
  httproutes "gateway.networking.k8s.io/httproute/v1"
)

appName: "rook"
#Charts: _
rgwDomain: "objects.home.josephmartin.org"

let namespace = c8s.#Namespace & {
  #name: "rook-system"
  metadata: labels: {
    "pod-security.kubernetes.io/enforce": "privileged"
    "pod-security.kubernetes.io/audit": "privileged"
    "pod-security.kubernetes.io/warn": "privileged"
  }
}
kustomizations: [_]: #defaultResourceNamespace: namespace

kustomizations: helm: "release": {
  ns: namespace
  (appName): helmrelease.#HelmRelease & {
    spec: {
      chart: spec: #Charts["rook-ceph"]
      interval: "10m0s"
      values: nodeSelector: storage: "yes"
    }
  }
}

#fluxResources: "kustomization:cluster": spec: wait: false
kustomizations: cluster: #dependsOn: [kustomizations.helm]
kustomizations: cluster: "manifest": {
  cluster: clusters.#CephCluster & {
    spec: {
      cephVersion: image: "quay.io/ceph/ceph:v18.2.1"
      dataDirHostPath: "/var/storage/rook",
      placement: all: nodeAffinity: requiredDuringSchedulingIgnoredDuringExecution: nodeSelectorTerms: [{
        matchExpressions: [{
          key: "storage"
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
  objectstore: objectstores.#CephObjectStore & {
    spec: {
      metadataPool: {
        failureDomain: "host"
        replicated: size: 3
      }
      dataPool: {
        failureDomain: "host"
        replicated: size: 3
      }
      preservePoolsOnDelete: false
      gateway: {
        port: 80
        securePort: 443
        sslCertificateRef: rgwCert.spec.secretName
        instances: 1
      }
    }
  }
  bucketStorageClass: storagev1.#StorageClass & {
    metadata: name: "rook-bucket-retained"
    provisioner: "rook-system.ceph.rook.io/bucket"
    reclaimPolicy: "Retain"
    parameters: {
      objectStoreName: objectstore.metadata.name
      objectStoreNamespace: objectstore.metadata.namespace
    }
  }
  rgwCert="rgw-cert": this=(certificates.#Certificate & {
    spec: {
      secretName: this.metadata.name
      dnsNames: [rgwDomain]
      issuerRef: {
        name: certmanager.kustomizations.$default.issuers.letsencrypt.metadata.name
        kind: certmanager.kustomizations.$default.issuers.letsencrypt.kind
      }
    }
  })
  gateway: gateways.#Gateway & {
    spec: {
      gatewayClassName: "cilium"
      listeners: [{
        name: "https"
        protocol: "HTTPS"
        port: 443
        hostname: rgwDomain
        tls: certificateRefs: [{
          kind: "Secret"
          name: rgwCert.spec.secretName
        }]
      }]
    }
  }
  route: httproutes.#HTTPRoute & {
    spec: {
      parentRefs: [{ name: gateway.metadata.name }]
      hostnames: [rgwDomain]
      rules: [{
        matches: [{
          path: {
            type: "PathPrefix"
            value: "/"
          }
        }]
        backendRefs: [{
          name: "rook-ceph-rgw-\(objectstore.metadata.name).\(kustomizations.helm.release.ns.metadata.name).svc"
          port: 80
        }]
      }]
    }
  }
}

objectStoreHost: "rook-ceph-rgw-\(kustomizations.cluster.manifest.objectstore.metadata.name).\(namespace.metadata.name).svc"
objectStorePort: kustomizations.cluster.manifest.objectstore.spec.gateway.port

//kustomizations: objectstore: #dependsOn: [kustomizations.helm]
//kustomizations: objectstore: "manifest": {
//}
