package netserv

import (
//  kafkas "kafka.strimzi.io/kafka/v1beta2"
  kafkausers "kafka.strimzi.io/kafkauser/v1beta2"
  externalsecrets "external-secrets.io/externalsecret/v1beta1"
  issuers "cert-manager.io/issuer/v1"
  corev1 "k8s.io/api/core/v1"
  rbacv1 "k8s.io/api/rbac/v1"
)

appName: "gerrit"

_affinity: {
  #label: string
  nodeAffinity: requiredDuringSchedulingIgnoredDuringExecution: nodeSelectorTerms: [{
    matchExpressions: [{
      key: "storage"
      operator: "In"
      values: ["yes"]
    }]
  }]
  podAntiAffinity: requiredDuringSchedulingIgnoredDuringExecution: [{
    labelSelector: matchExpressions: [{
      key: "app"
      operator: "In"
      values: [#label]
    }]
    topologyKey: "kubernetes.io/hostname"
  }]
}

kustomizations: $default: manifest: {
  ns: #AppNamespace
  //"events-broker": kafkas.#Kafka & {
  broker="events-broker": {
    apiVersion: "kafka.strimzi.io/v1beta2"
    kind: "Kafka"
    spec: {
      entityOperator: {
        userOperator: {}
        topicOperator: {}
      }
      kafka: {
        replicas: 3
        version: "3.6.1"
        logging: {
          type: "inline"
          //loggers: "kafka.root.logger.level": "INFO"
        }
        readinessProbe: {
          initialDelaySeconds: 15
          timeoutSeconds: 5
        }
        livenessProbe: {
          initialDelaySeconds: 15
          timeoutSeconds: 5
        }
        listeners: [{
          port: 9092
          name: "listener"
          type: "internal"
          tls: true
          authentication: type: "tls"
          configuration: useServiceDnsDomain: true
        }]
        storage: {
          type: "persistent-claim"
          class: "local-hostpath"
          size: "20Gi"
        }
        template: {
          pod: {
            metadata: labels: app: "gerrit-kafka"
            affinity: _affinity & {#label: metadata.labels.app}
          }
        }
      }
      zookeeper: {
        replicas: 3
        logging: {
          type: "inline"
          //loggers: "zookeeper.root.logger": "INFO"
        }
        storage: {
          type: "persistent-claim"
          class: "local-hostpath"
          size: "10Gi"
        }
        template: {
          pod: {
            metadata: labels: app: "gerrit-zookeeper"
            affinity: _affinity & {#label: metadata.labels.app}
          }
        }
      }
    }
  }
  kafkaUser: kafkausers.#KafkaUser & {
    metadata: name: "gerrit"
    spec: authentication: type: "tls"
  }

  storeServiceAccount: corev1.#ServiceAccount & {
    metadata: name: "bucket-secrets-store"
  }
  // TODO restrict to specific secrets
  storeRole: rbacv1.#Role & {
    metadata: name: "gerrit-secrets-store"
    rules: [{
      apiGroups: [""]
      resources: ["secrets"]
      verbs: ["get", "watch", "list"]
    }]
  }
  storeRoleBinding: rbacv1.#RoleBinding & {
    metadata: name: "gerrit-secrets-store"
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
  store="gerrit-secrets-store": {
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
  caSecret: externalsecrets.#ExternalSecret & {
    metadata: name: "\(broker.metadata.name)-cluster-ca-synced"
    spec: {
      secretStoreRef: {
        name: store.metadata.name
        kind: store.kind
      }
      refreshInterval: "1h"
      target: {
        name: metadata.name
        deletionPolicy: "Delete"
        creationPolicy: "Owner"
      }
      data: [
        {
          secretKey: "tls.key"
          remoteRef: {
            key: "\(broker.metadata.name)-cluster-ca"
            property: "ca.key"
          }
        },
        {
          secretKey: "tls.crt"
          remoteRef: {
            key: "\(broker.metadata.name)-cluster-ca-cert"
            property: "ca.crt"
          }
        },
      ]
    }
  }
  "cluster-ca": issuers.#Issuer & {
    spec: ca: secretName: caSecret.metadata.name
  }
}
