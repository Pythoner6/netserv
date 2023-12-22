package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
  bgppolicy   "cilium.io/ciliumbgppeeringpolicy/v2alpha1"
)

appName: "cilium"

kustomizations: helm: "manifest.yaml": {
  resources: {
    (appName): helmrelease.#HelmRelease & {
      metadata: namespace: "kube-system"
      spec: {
        chart: spec: #Charts[appName]
        interval: "10m0s"
        values: {
          bgpControlPlane: enabled: true
          hubble: {
            tls: auto: method: "cronJob"
            relay: enabled: true
            ui: enabled: true
          }
          clustermesh: apiserver: tls: auto: method: "cronJob"
          ipam: mode: "kubernetes"
          kubeProxyReplacement: true
          securityContext: capabilities: {
            ciliumAgent: ["CHOWN","KILL","NET_ADMIN","NET_RAW","IPC_LOCK","SYS_ADMIN","SYS_RESOURCE","DAC_OVERRIDE","FOWNER","SETGID","SETUID"]
            cleanCiliumState: ["NET_ADMIN","SYS_ADMIN","SYS_RESOURCE"]
          }
          cgroup: {
            autoMount: enabled: false
            hostRoot: "/sys/fs/cgroup"
          }
          k8sServiceHost: "localhost"
          k8sServicePort: 7445

        }
      }
    }
  }
}

kustomizations: bgp: "manifest.yaml": {
  clusterResources: {
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
