package netserv

import (
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
)

appName: "democratic-csi"
#Charts: _

let storagePath = "/var/storage/democratic-csi"

kustomizations: helm: "release": {
  ns: #AppNamespace
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
        storageClasses: [{
          name: "local-hostpath"
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
