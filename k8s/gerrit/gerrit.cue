package netserv

import (
//  kafkas "kafka.strimzi.io/kafka/v1beta2"
  kafkausers "kafka.strimzi.io/kafkauser/v1beta2"
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
  "events-broker": {
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
}
