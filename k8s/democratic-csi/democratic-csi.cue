package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

appName: "democratic-csi"
#Charts: _

let storagePath = "/var/storage/democratic-csi"

localHostpath: "local-hostpath"

kustomizations: helm: "release": {
  ns: #AppNamespace & {
    metadata: labels: {
      "pod-security.kubernetes.io/enforce": "privileged"
      "pod-security.kubernetes.io/audit": "privileged"
      "pod-security.kubernetes.io/warn": "privileged"
    }
  }
  "local-hostpath": helmrelease.#HelmRelease & {
    spec: {
      chart: spec: #Charts[appName]
      interval: "10m0s"
      values: {
        csiDriver: {
          name: "org.democratic-csi.local-hostpath"
          attachRequired: false
          storageCapacity: true
          fsGroupPolicy: "File"
        }
        controller: {
          enabled: true
          strategy: "node"
          externalProvisioner: extraArgs: [
            "--leader-election=false",
            "--node-deployment=true",
            "--node-deployment-immediate-binding=false",
            "--feature-gates=Topology=true",
            "--strict-topology=true",
            "--enable-capacity=true",
            "--capacity-ownerref-level=1",
          ]
          externalAttacher: enabled: false
          externalResizer: enabled: false
          externalSnapshotter: {
            enabled: false
            extraArgs: ["--leader-election=false", "--node-deployment=true"]
          }
        }
        storageClasses: [{
          name: localHostpath
          defaultClass: false
          reclaimPolicy: "Delete"
          volumeBindingMode: "WaitForFirstConsumer"
          allowVolumeExpansion: true
        }]
        driver: config: {
          driver: "local-hostpath"
          "local-hostpath": {
            shareBasePath: storagePath
            controllerBasePath: storagePath
            dirPermissionsMode: "0770"
            dirPermissionsUser: 0
            dirPermissionsGroup: 0
          }
        }
        node: {
          driver: extraVolumeMounts: [{
            name: "local-storage"
            mountPath: storagePath
            mountPropagation: "Bidirectional"
          }]
          extraVolumes: [{
            name: "local-storage"
            hostPath: {
              path: storagePath
              type: "DirectoryOrCreate"
            }
          }]
        }
      }
    }
  }
}
