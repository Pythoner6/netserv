package netserv

import (
//  kafkas "kafka.strimzi.io/kafka/v1beta2"
  kafkausers "kafka.strimzi.io/kafkauser/v1beta2"
  kafkanodepools "kafka.strimzi.io/kafkanodepool/v1beta2"
  scyllaclusters "scylla.scylladb.com/scyllacluster/v1"
  scyllaoperator "pythoner6.dev/netserv/k8s/scylla-operator:netserv"
  //externalsecrets "external-secrets.io/externalsecret/v1beta1"
  //issuers "cert-manager.io/issuer/v1"
  corev1 "k8s.io/api/core/v1"
  //rbacv1 "k8s.io/api/rbac/v1"
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

kustomizations: $default: #dependsOn: [scyllaoperator.kustomizations.helm]
kustomizations: $default: manifest: {
  ns: #AppNamespace & {
    metadata: labels: {
      "pod-security.kubernetes.io/enforce": "privileged"
      "pod-security.kubernetes.io/audit": "privileged"
      "pod-security.kubernetes.io/warn": "privileged"
    }
  }
  "scylla-config": corev1.#ConfigMap & {
    data: "scylla.yaml": """
    alternator_enforce_authorization: true
    """
  }
  "global-refdb": scyllaclusters.#ScyllaCluster & {
    spec: {
      version: "5.2.15"
      alternator: {
        port: 8000
        writeIsolation: "always"
      }
      datacenter: {
        name: "us-east-1"
        racks: [{
          name: "us-east-1a"
          members: 3
          resources: {
            requests: {
              cpu: "1"
              memory: "3Gi"
            }
            limits: {
              cpu: "1"
              memory: "3Gi"
            }
          }
          storage: {
            capacity: "10G"
            storageClassName: "local-hostpath"
          }
          placement: _affinity & {#label: "global-refdb"}
        }]
      }
    }
  }
  "events-broker-node-pool": kafkanodepools.#KafkaNodePool & {
    metadata: labels: "strimzi.io/cluster": broker.metadata.name
    spec: {
      replicas: 3
      roles: ["controller", "broker"]
      storage: {
        type: "persistent-claim"
        class: "local-hostpath"
        size: "20Gi"
      }
    }
  }
  //broker="events-broker": kafkas.#Kafka & {
  broker="events-broker": {
    apiVersion: "kafka.strimzi.io/v1beta2"
    kind: "Kafka"
    metadata: annotations: "strimzi.io/kraft": "enabled"
    metadata: annotations: "strimzi.io/node-pools": "enabled"
    spec: {
      entityOperator: {
        userOperator: {}
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
        // Ignored because of kraft mode
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
      // Ignored because of kraft mode
      zookeeper: {
        replicas: 3
        storage: {
          type: "persistent-claim"
          class: "local-hostpath"
          size: "10Gi"
        }
      }
    }
  }
  kafkaUser: kafkausers.#KafkaUser & {
    metadata: name: "gerrit"
    spec: authentication: type: "tls"
  }

  //"cluster-ca": issuers.#Issuer & {
  //  spec: ca: secretName: caSecret.metadata.name
  //}
}
