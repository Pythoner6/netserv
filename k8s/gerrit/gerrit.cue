package netserv

import (
//  kafkas "kafka.strimzi.io/kafka/v1beta2"
  kafkausers "kafka.strimzi.io/kafkauser/v1beta2"
  kafkanodepools "kafka.strimzi.io/kafkanodepool/v1beta2"
  scyllaclusters "scylla.scylladb.com/scyllacluster/v1"
  scyllaoperator "pythoner6.dev/netserv/k8s/scylla-operator:netserv"
  //externalsecrets "external-secrets.io/externalsecret/v1beta1"
  issuers "cert-manager.io/issuer/v1"
  corev1 "k8s.io/api/core/v1"
  //batchv1 "k8s.io/api/batch/v1"
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
  refdbConfig="global-refdb-config": corev1.#ConfigMap & {
    data: "scylla.yaml": """
    authenticator: com.scylladb.auth.CertificateAuthenticator
    alternator_enforce_authorization: true
    auth_superuser_name: admin
    auth_certificate_role_queries:
    - source: SUBJECT
      query: CN=([a-zA-Z0-9_-]+)
    """
  }
  refdb="global-refdb": scyllaclusters.#ScyllaCluster & {
    spec: {
      version: "5.4.3"
      alternator: {
        port: 8000
        writeIsolation: "always"
      }
      datacenter: {
        name: "us-east-1"
        racks: [{
          name: "us-east-1a"
          members: 3
          scyllaConfig: refdbConfig.metadata.name
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
  refdbIssuer="global-refdb-ca": issuers.#Issuer & {
    spec: ca: secretName: "\(refdb.metadata.name)-local-client-ca"
  }
  //"global-refdb-gerrit-credentials": batchv1.#Job & {
  "global-refdb-gerrit-credentials":  {
    apiVersion: "batch/v1"
    kind: "Job"
    spec: template: spec: {
      restartPolicy: "OnFailure"
      containers: [{
        name: "gerrit-credentials"
        image: "ghcr.io/pythoner6/netserv/gerrit@\(#Images[appName].digest)"
        command: [
          "alternator-credentials", "generate",
          "--ca", "/certs/ca/tls.crt",
          "--cert", "/certs/admin/tls.crt",
          "--key", "/certs/admin/tls.key",
          "--nodes", "\(refdb.metadata.name)-client.\(appName).svc:9142",
          "--role", "gerrit",
        ]
        volumeMounts: [
          {
            mountPath: "/certs/ca/"
            name: "ca"
          },
          {
            mountPath: "/certs/admin/"
            name: "admin"
          },
        ]
      }]
      volumes: [
        {
          name: "ca"
          secret: {
            items: [{key: "tls.crt", path: "tls.crt"}]
            secretName: "\(refdb.metadata.name)-local-serving-ca"
          }
        },
        {
          name: "admin"
          csi: {
            driver: "csi.cert-manager.io"
            readOnly: true
            volumeAttributes: {
              "csi.cert-manager.io/issuer-name": refdbIssuer.metadata.name
              "csi.cert-manager.io/common-name": "admin"
            }
          }
        },
      ]
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
    metadata: labels: "strimzi.io/cluster": broker.metadata.name
    spec: authentication: type: "tls"
  }
}
