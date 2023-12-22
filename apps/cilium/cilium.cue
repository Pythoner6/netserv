package netserv

import (
  "encoding/yaml"

  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
  bgppolicy   "cilium.io/ciliumbgppeeringpolicy/v2alpha1"
  ippool      "cilium.io/ciliumloadbalancerippool/v2alpha1"
)

appName: "cilium"

kustomizations: "gateway-crds": {
  _extraManifests: yaml.Unmarshal(extraManifests)
}

kustomizations: helm: _dependsOn: [kustomizations."gateway-crds"]
kustomizations: helm: "manifest.yaml": {
  resources: {
    (appName): helmrelease.#HelmRelease & {
      metadata: namespace: "kube-system"
      spec: {
        chart: spec: #Charts[appName]
        interval: "10m0s"
        values: {
          image: override: "ghcr.io/pythoner6/cilium:latest@sha256:bfeec1e09b5c25cadeac7f8cb5f30ad3f4dcac59f72a01e56c97b340c464e3ae"
          bgpControlPlane: enabled: true
          hubble: {
            tls: auto: method: "cronJob"
            relay: enabled: true
            ui: enabled: true
          }
          clustermesh: apiserver: tls: auto: method: "cronJob"
          ipam: mode: "kubernetes"
          kubeProxyReplacement: true
          l7Proxy: true
          gatewayAPI: enabled: true
          rolloutCiliumPods: true
          operator: {
            rolloutPods: true
            image: override: "ghcr.io/pythoner6/operator-generic:latest@sha256:789fd0bafc7e60221bce5b9ac6c233ea86a0ffe9765606e52b3860b4ee9c734b"
          }
          ingressController: {
            enabled: true
            default: true
            loadBalancerMode: "dedicated"
          }

          // Required for Talos
          securityContext: capabilities: {
            ciliumAgent: ["CHOWN","KILL","NET_ADMIN","NET_RAW","IPC_LOCK","SYS_ADMIN","SYS_RESOURCE","DAC_OVERRIDE","FOWNER","SETGID","SETUID"]
            cleanCiliumState: ["NET_ADMIN","SYS_ADMIN","SYS_RESOURCE"]
          }
          cgroup: {
            autoMount: enabled: false
            hostRoot: "/sys/fs/cgroup"
          }
          // Use Talos' kubeprism endpoint
          k8sServiceHost: "localhost"
          k8sServicePort: 7445
        }
      }
    }
  }
}

kustomizations: bgp: _dependsOn: [kustomizations.helm]
kustomizations: bgp: "manifest.yaml": {
  clusterResources: {
    "default-pool": ippool.#CiliumLoadBalancerIPPool & {
      spec: blocks: [{cidr: "10.16.3.0/24"}]
    }
    default: bgppolicy.#CiliumBGPPeeringPolicy & { spec: {
      nodeSelector: matchLabels: "pythoner6.dev/bgp-policy": "default"
      virtualRouters: [{
        localASN: 64512
        exportPodCIDR: false
        serviceSelector: matchExpressions: [{key: "bgp", operator: "NotIn", values: ["disabled"]}]
        neighbors: [{
          peerAddress: "10.16.2.2/32"
          peerASN: 64512
          eBGPMultihopTTL: 10
          connectRetryTimeSeconds: 120
          holdTimeSeconds: 90
          keepAliveTimeSeconds: 30
          gracefulRestart: {
            enabled: true
            restartTimeSeconds: 120
          }
        }]
      }]
    }}
  }
}
