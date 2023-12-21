package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
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
