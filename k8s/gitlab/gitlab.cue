package netserv

import (
  dcsi "pythoner6.dev/netserv/k8s/democratic-csi:netserv"
  cnpg "pythoner6.dev/netserv/k8s/cnpg:netserv"
  rook "pythoner6.dev/netserv/k8s/rook:netserv"
  certmanager "pythoner6.dev/netserv/k8s/cert-manager:netserv"
  clusters "postgresql.cnpg.io/cluster/v1"
  //secretstores "external-secrets.io/secretstore/v1beta1"
  helmrelease "helm.toolkit.fluxcd.io/helmrelease/v2beta2"
  corev1 "k8s.io/api/core/v1"
  rbacv1 "k8s.io/api/rbac/v1"
  "pythoner6.dev/c8s"
)

appName: "gitlab"
#Charts: _

let nodeAffinity = {
  nodeAffinity: requiredDuringSchedulingIgnoredDuringExecution: nodeSelectorTerms: [{
    matchExpressions: [{
      key: "storage"
      operator: "In"
      values: ["yes"]
    }]
  }]
}

kustomizations: $default: #dependsOn: [dcsi.kustomizations.helm, cnpg.kustomizations.helm, rook.kustomizations.cluster]
kustomizations: $default: manifest: {
  ns: #AppNamespace
  runnerNs: c8s.#Namespace & {
    #name: "gitlab-runners"
    metadata: labels: {
      "pod-security.kubernetes.io/enforce": "privileged"
      "pod-security.kubernetes.io/audit": "privileged"
      "pod-security.kubernetes.io/warn": "privileged"
    }
  }
  "gitlab-db": clusters.#Cluster & {
    spec: {
      instances: 3
      maxSyncReplicas: 2
      minSyncReplicas: 2
      storage: {
        storageClass: dcsi.localHostpath
        size: "10Gi"
      }
      affinity: nodeAffinity
    }
  }
  "praefect-db": clusters.#Cluster & {
    spec: {
      instances: 3
      maxSyncReplicas: 2
      minSyncReplicas: 2
      storage: {
        storageClass: dcsi.localHostpath
        size: "1Gi"
      }
      affinity: nodeAffinity
    }
  }
  "registry-db": clusters.#Cluster & {
    spec: {
      instances: 3
      maxSyncReplicas: 2
      minSyncReplicas: 2
      storage: {
        storageClass: dcsi.localHostpath
        size: "10Gi"
      }
      affinity: nodeAffinity
    }
  }
  storeServiceAccount: corev1.#ServiceAccount & {
    metadata: name: "bucket-secrets-store"
  }
  // TODO restrict to specific secrets
  storeRole: rbacv1.#Role & {
    metadata: name: "bucket-secrets-store"
    rules: [{
      apiGroups: [""]
      resources: ["secrets"]
      verbs: ["get", "watch", "list"]
    }]
  }
  storeRoleBinding: rbacv1.#RoleBinding & {
    metadata: name: "bucket-secrets-store"
    subjects: [{
      kind: storeServiceAccount.kind
      name: storeServiceAccount.metadata.name
      apiGroup: ""
    }]
    roleRef: {
      kind: storeRole.kind
      name: storeRole.metadata.name
      apiGroup: "rbac.authorization.k8s.io"
    }
  }
  store="bucket-secrets-store": {
    // CUE MaxFields is broken so the ES CRD doesn't validate right now
    apiVersion: "external-secrets.io/v1beta1"
    kind: "SecretStore"
    spec: provider: kubernetes: {
      remoteNamespace: store.metadata.namespace
      server: caProvider: {
        type: "ConfigMap"
        name: "kube-root-ca.crt"
        key: "ca.crt"
      }
      auth: serviceAccount: name: storeServiceAccount.metadata.name
    }
  }

  lfsBucket: #BucketClaim & { metadata: name: "git-lfs" }
  lfsSecret: #BucketSecret & { #bucket: lfsBucket, #store: store }

  artifactsBucket: #BucketClaim & { metadata: name: "gitlab-artifacts" }
  artifactsSecret: #BucketSecret & { #bucket: artifactsBucket, #store: store }

  uploadsBucket: #BucketClaim & { metadata: name: "gitlab-uploads" }
  uploadsSecret: #BucketSecret & { #bucket: uploadsBucket, #store: store }

  packagesBucket: #BucketClaim & { metadata: name: "gitlab-packages" }
  packagesSecret: #BucketSecret & { #bucket: packagesBucket, #store: store }

  registryBucket: #BucketClaim & { metadata: name: "gitlab-registry" }
  registrySecret: #RegistryBucketSecret & { #bucket: registryBucket, #store: store }
}

let gitlabDbRw = kustomizations["$default"].manifest["gitlab-db"].metadata.name + "-rw"
let gitlabDbPass = kustomizations["$default"].manifest["gitlab-db"].metadata.name + "-app"
let praefectDbRw = kustomizations["$default"].manifest["praefect-db"].metadata.name + "-rw"
let praefectDbPass = kustomizations["$default"].manifest["praefect-db"].metadata.name + "-app"
let registryDbRw = kustomizations["$default"].manifest["registry-db"].metadata.name + "-rw"
let registryDbPass = kustomizations["$default"].manifest["registry-db"].metadata.name + "-app"

kustomizations: helm: #dependsOn: [kustomizations["$default"]]
kustomizations: helm: manifest: {
  (appName): this=(helmrelease.#HelmRelease & {
    spec: {
      chart: spec: #Charts[appName]
      interval: "10m0s"
      values: {
        global: {
          edition: "ce"
          hosts: domain: "home.josephmartin.org"
          nodeSelector: storage: "yes"
          gitaly: enabled: true
          minio: enabled: false
          ingress: {
            configureCertmanager: false
            annotations: {
              "kubernetes.io/tls-acme": true
              "cert-manager.io/cluster-issuer": certmanager.kustomizations.$default.issuers.letsencrypt.metadata.name
            }
          }
          email: {
            display_name: "GitLab"
            from: "gitlab@josephmartin.org"
            reply_to: "noreply@josephmartin.org"
          }
          smtp: {
            enabled: true
            address: "email-smtp.us-east-1.amazonaws.com"
            port: 465
            tls: true
            authentication: "plain"
            user_name: "AKIA4VTDNU4RRNM6OQA2"
            password: {
              secret: "gitlab-email-secret"
              key: "password"
            }
          }
          pages: enabled: false
          psql: {
            host: gitlabDbRw
            database: "app"
            username: "app"
            password: {
              secret: gitlabDbPass
              key: "password"
            }
          }
          praefect: {
            enabled: true
            dbSecret: {
              secret: praefectDbPass
              key: "password"
            }
            psql: {
              user: "app"
              dbName: "app"
              host: praefectDbRw
            }
            virtualStorages: [{
              name: "default"
              gitalyReplicas: 3
              maxUnavailable: 1
              persistence: {
                enabled: true
                size: "50Gi"
                accessMode: "ReadWriteOnce"
                storageClass: dcsi.localHostpath
                defaultReplicationFactor: 3
              }
            }]
          }
          appConfig: {
            lfs: {
              enabled: true
              proxy_download: true
              bucket: kustomizations["$default"].manifest.lfsBucket.spec.bucketName
              connection: secret: kustomizations["$default"].manifest.lfsSecret.metadata.name
            }
            artifacts: {
              enabled: true
              proxy_download: true
              bucket: kustomizations["$default"].manifest.artifactsBucket.spec.bucketName
              connection: secret: kustomizations["$default"].manifest.artifactsSecret.metadata.name
            }
            uploads: {
              enabled: true
              proxy_download: true
              bucket: kustomizations["$default"].manifest.uploadsBucket.spec.bucketName
              connection: secret: kustomizations["$default"].manifest.uploadsSecret.metadata.name
            }
            packages: {
              enabled: true
              proxy_download: true
              //bucket: kustomizations["default"].manifest.packagesBucket.spec.bucketName
              connection: secret: kustomizations["$default"].manifest.packagesSecret.metadata.name
            }
          }
        }
        "certmanager": install: false
        "certmanager-issuer": install: false
        prometheus: install: false
        postgresql: install: false
        "gitlab-runner": {
          install: true
          replicas: 3
          nodeSelector: storage: "yes"
          unregisterRunners: true
          rbac: {
            create: true
            clusterWideAccess: true
          }
          runners: config: """
            [[runners]]
              [runners.kubernetes]
                namespace = "\(kustomizations.$default.manifest.runnerNs.metadata.name)"
                image = "alpine"
                privileged = true
              [runners.kubernetes.node_selector]
                "kubernetes.io/arch" = "amd64"
                "kubernetes.io/os" = "linux"
          """
        }
        gitlab: {
          webservice: ingress: tls: secretName: "\(this.metadata.name)-gitlab-tls"
          kas: ingress: tls: secretName: "\(this.metadata.name)-kas-tls"
          toolbox: enabled: false
        }
        redis: {
          master: nodeSelector: storage: "yes"
          global: storageClass: dcsi.localHostpath
        }
        registry: {
          ingress: tls: secretName: "\(this.metadata.name)-registry-tls"
          storage: {
            secret: kustomizations["$default"].manifest.registrySecret.metadata.name
            redirect: disable: true
          }
          database: {
            enabled: true
            host: registryDbRw
            user: "app"
            name: "app"
            password: secret: registryDbPass
          }
        }
      }
    }
  })
}
