package netserv

import (
  "strconv"
  rook "pythoner6.dev/netserv/k8s/rook:netserv"
  bucketclaims "objectbucket.io/objectbucketclaim/v1alpha1"
  externalsecrets "external-secrets.io/externalsecret/v1beta1"
)

#BucketClaim: this=(bucketclaims.#ObjectBucketClaim & {
  spec: {
    bucketName: this.metadata.name
    storageClassName: rook.kustomizations.cluster.manifest.bucketStorageClass.metadata.name
  }
})

let objectStoreUrl = "http://\(rook.objectStoreHost):\(strconv.FormatInt(rook.objectStorePort,10))"

#BucketSecret: externalsecrets.#ExternalSecret & {
  #bucket: _
  #store: _
  metadata: name: #bucket.metadata.name
  spec: {
    secretStoreRef: {
      name: #store.metadata.name
      kind: #store.kind
    }
    refreshInterval: "0"
    target: {
      name: metadata.name
      deletionPolicy: "Merge"
      creationPolicy: "Merge"
      template: {
        engineVersion: "v2"
        data:
          connection: """
          provider: AWS
          path_style: true
          host: \(strconv.Quote(rook.objectStoreHost))
          endpoint: \(strconv.Quote(objectStoreUrl))
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
