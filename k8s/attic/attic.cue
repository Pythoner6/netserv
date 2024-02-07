package netserv

import (
  certmanager "pythoner6.dev/netserv/k8s/cert-manager:netserv"
  corev1 "k8s.io/api/core/v1"
  appsv1 "k8s.io/api/apps/v1"
  clusters "postgresql.cnpg.io/cluster/v1"
  password "generators.external-secrets.io/password/v1alpha1"
  //externalsecrets "external-secrets.io/externalsecret/v1beta1"
  certificates "cert-manager.io/certificate/v1"
  claims "objectbucket.io/objectbucketclaim/v1alpha1"
  gateways "gateway.networking.k8s.io/gateway/v1"
  httproutes "gateway.networking.k8s.io/httproute/v1"
)

appName: "attic"
domain: "attic.home.josephmartin.org"

kustomizations: $default: "manifest": {
  ns: #AppNamespace
  secretGenerator="hs256-base64": password.#Password & {
    spec: {
      length: 48
      symbols: 48
      digits: 0
      symbolCharacters: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/"
      allowRepeat: true
    }
  }
  secret="admin-secret": {
    apiVersion: "external-secrets.io/v1beta1"
    kind: "ExternalSecret"
    spec: {
      refreshInterval: "0"
      dataFrom: [{sourceRef: generatorRef: {
        apiVersion: secretGenerator.apiVersion
        kind: secretGenerator.kind
        name: secretGenerator.metadata.name
      }}]
    }
  }
  configMap: corev1.#ConfigMap & {
    metadata: name: "attic-server"
    data: "gen-config.sh": """
      cat <<EOF > /config/server.toml
      api-endpoint = "https://attic.home.josephmartin.org/"
      token-hs256-secret-base64 = "$(cat /secrets/password)"

      [database]
      [chunking]
      nar-size-threshold = 65536 # chunk files that are 64 KiB or larger
      min-size = 16384           # 16 KiB
      avg-size = 65536           # 64 KiB
      max-size = 262144          # 256 KiB
      [compression]
      type = "zstd"
      [storage]
      type = "s3"
      region = "$BUCKET_REGION"
      bucket = "$BUCKET_NAME"
      endpoint = "http://$BUCKET_HOST"
      EOF
      """
  }
  bucketClaim="attic-storage": this=(claims.#ObjectBucketClaim & {
    spec: {
      generateBucketName: this.metadata.name
      storageClassName: "rook-bucket-retained"
    }
  })
  db="attic-db": clusters.#Cluster & {
    spec: {
      instances: 3
      maxSyncReplicas: 2
      minSyncReplicas: 2
      storage: {
        storageClass: "local-hostpath"
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
  deployment="attic-server": this=(appsv1.#Deployment & {
    metadata: labels: app: this.metadata.name
    spec: {
      replicas: 1
      selector: matchLabels: app: this.metadata.name
      template: {
        metadata: labels: app: this.metadata.name
        spec: {
          nodeSelector: "kubernetes.io/arch": "amd64"
          initContainers: [{
            name: "config"
            image: "alpine:3.19.0"
            command: ["/bin/sh", "/gen-config.sh"]
            volumeMounts: [{
              name: "config"
              mountPath: "/config"
            },{
              name: "gen-config"
              mountPath: "/gen-config.sh"
              subPath: "gen-config.sh"
            },{
              name: "secrets"
              mountPath: "/secrets"
            }]
            envFrom: [{ 
              configMapRef: name: bucketClaim.metadata.name 
            },{
              secretRef: name: bucketClaim.metadata.name
            }]
          }]
          containers: [{
            name: "attic"
            image: "ghcr.io/zhaofengli/attic:latest"
            ports: [{ containerPort: 8080 }]
            env: [{
              name: "ATTIC_SERVER_DATABASE_URL"
              valueFrom: secretKeyRef: {
                key: "uri"
                name: "\(db.metadata.name)-app"
              }
            }]
            envFrom: [{ secretRef: name: bucketClaim.metadata.name }]
            volumeMounts: [{
              name: "config"
              mountPath: "/var/empty/.config/attic/server.toml"
              subPath: "server.toml"
            }]
          }]
          volumes: [{
            name: "gen-config"
            "configMap": name: configMap.metadata.name
          },{
            name: "config"
            emptyDir: {}
          },{
            name: "secrets"
            "secret": secretName: secret.metadata.name
          }]
        }
      }
    }
  })
  service: corev1.#Service & {
    metadata: name: "attic-server"
    spec: {
      selector: app: deployment.spec.template.metadata.labels.app
      ports: [{
        protocol: "TCP"
        port: 80
        targetPort: 8080
      }]
    }
  }
  cert="attic-cert": this=(certificates.#Certificate & {
    spec: {
      secretName: this.metadata.name
      dnsNames: [domain]
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
        hostname: domain
        tls: certificateRefs: [{
          kind: "Secret"
          name: cert.spec.secretName
        }]
      }]
    }
  }
  route: httproutes.#HTTPRoute & {
    spec: {
      parentRefs: [{ name: gateway.metadata.name }]
      hostnames: [domain]
      rules: [{
        matches: [{
          path: {
            type: "PathPrefix"
            value: "/"
          }
        }]
        backendRefs: [{
          name: service.metadata.name
          port: 80
        }]
      }]
    }
  }
}

