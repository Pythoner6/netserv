package kustomization

import (
  "list"
  "encoding/yaml"
)

#Resource: {
  file: string
  priority: int | *0
}
#Resources: {
  resources: {
    file: "./resources.yaml"
  }
}
#Kustomization: {
  apiVersion: "kustomize.config.k8s.io/v1beta1"
  kind: "Kustomization"
  resources: [ for r in list.Sort([ for _, r in #Resources {r} ], {
    list.Comparer
    T: #Resource
    x: T
    y: T
    less: x.priority > y.priority
  }) {r.file} ]
}

kustomization: yaml.MarshalStream([#Kustomization])
