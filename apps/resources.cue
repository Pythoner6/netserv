package resources

import (
  "encoding/yaml"
  //"list"
  //"pythoner6.dev/test/foo"
  corev1 "k8s.io/api/core/v1"
)

#Namespace: corev1.#Namespace & {
  _name: string
  apiVersion: "v1"
  kind: "Namespace"
  metadata: {
    name: _name
  }
}
#WithNamespace: {
  metadata: {
    namespace: string | *#Namespace.metadata.name
    ...
  }
  ...
}
#WithoutNamespace: {
  metadata: {
    namespace?: _|_
    ...
  }
  ...
}
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

#ClusterResources: {[_]: #WithoutNamespace}
#Resources: {[_]: #WithNamespace}

resources: yaml.MarshalStream([ for _, r in #ClusterResources {r}, for _, r in #Resources {r} ])
