package netserv

import (
  "strconv"
  dcsi "pythoner6.dev/netserv/k8s/democratic-csi:netserv"
  cnpg "pythoner6.dev/netserv/k8s/cnpg:netserv"
  rook "pythoner6.dev/netserv/k8s/rook:netserv"
  clusters "postgresql.cnpg.io/cluster/v1"
  bucketclaims "objectbucket.io/objectbucketclaim/v1alpha1"
  //secretstores "external-secrets.io/secretstore/v1beta1"
  externalsecrets "external-secrets.io/externalsecret/v1beta1"
  corev1 "k8s.io/api/core/v1"
  rbacv1 "k8s.io/api/rbac/v1"
)

appName: "gitlab"
#Charts: _

#BucketClaim: this=(bucketclaims.#ObjectBucketClaim & {
  spec: {
    bucketName: this.metadata.name
    storageClassName: rook.kustomizations.cluster.manifest.bucketStorageClass.metadata.name
  }
})

kustomizations: $default: #dependsOn: [dcsi.kustomizations.helm, cnpg.kustomizations.helm, rook.kustomizations.cluster]
kustomizations: $default: manifest: {
  ns: #AppNamespace
  db: clusters.#Cluster & {
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
  praefectDb: clusters.#Cluster & {
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
  storeServiceAccount: corev1.#ServiceAccount & {
    apiVersion: "v1"
    kind: "ServiceAccount"
    metadata: name: "bucket-secrets-store"
  }
  // TODO restrict to specific secrets
  storeRole: rbacv1.#Role & {
    apiVersion: "rbac.authorization.k8s.io/v1"
    kind: "Role"
    metadata: name: "bucket-secrets-store"
    rules: [{
      apiGroups: [""]
      resources: ["secrets"]
      verbs: ["get", "watch", "list"]
    }]
  }
  storeRoleBinding: rbacv1.#RoleBinding & {
    apiVersion: "rbac.authorization.k8s.io/v1"
    kind: "RoleBinding"
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
  lfsSecret: externalsecrets.#ExternalSecret & {
    metadata: name: lfsBucket.metadata.name
    spec: {
      secretStoreRef: {
        name: store.metadata.name
        kind: store.kind
      }
      refreshInterval: "0"
      target: {
        name: metadata.name
        deletionPolicy: "Owner"
        creationPolicy: "Merge"
        template: {
          engineVersion: "v2"
          data:
            connection: """
            provider: AWS
            path_style: true
            host: \(strconv.Quote(rook.objectStoreHost))
            endpoint: \(strconv.Quote("http://" + rook.objectStoreHost + ":" + strconv.FormatInt(rook.objectStorePort, 10)))
            region: ""
            aws_signature_version: 4
            aws_access_key_id: {{ .aws_access_key_id | quote }}
            aws_secret_access_key: {{ .aws_secret_access_key | quote }}
            """
        }
      }
      data: [
        {
          secretKey: "aws_access_key_id"
          remoteRef: {
            key: metadata.name
            property: "AWS_ACCESS_KEY_ID"
          }
        },
        {
          secretKey: "aws_secret_access_key"
          remoteRef: {
            key: metadata.name
            property: "AWS_SECRET_ACCESS_KEY"
          }
        },
      ]
    }
  }

  artifactsBucket: #BucketClaim & { metadata: name: "gitlab-artifacts" }

  uploadsBucket: #BucketClaim & { metadata: name: "gitlab-uploads" }

  packagesBucket: #BucketClaim & { metadata: name: "gitlab-packages" }
}

//kustomizations: helm: #dependsOn: [kustomizations["$default"]]
//kustomizations: helm: manifest: {
//}
