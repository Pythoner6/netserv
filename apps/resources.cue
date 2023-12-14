package resources

import (
  "encoding/yaml"
  corev1 "k8s.io/api/core/v1"
)

// Default namespace. Name defined in leaf directory
#Namespace: corev1.#Namespace & {
  _name: string
  metadata: name: _name
}

// Object reference helper
#Ref: {
  _obj: { 
    apiVersion: string
    kind: string
    metadata: {
      name: string
      namespace?: string
      ...
    }
    ...
  }
  apiVersion: _obj.apiVersion
  kind: _obj.kind
  if _obj.metadata.namespace != _|_ {
    namespace: _obj.metadata.namespace
  }
  name: _obj.metadata.name
}

// Cluster scoped resources should not have a namespace
#ClusterResources: {[_]: {metadata: namespace?: _|_}}
// On namespaced resources, set the default namespace
#Resources: {[_]: {metadata: namespace: string | *#Namespace.metadata.name}}

// Exported string of yaml documents
resources: yaml.MarshalStream([
  for _, r in #ClusterResources {r},
  for _, r in #Resources {r},
])
