package netserv

import (
  "path"
  "strings"

  corev1 "k8s.io/api/core/v1"
  kustomization "kustomize.toolkit.fluxcd.io/kustomization/v1"
  ocirepository "source.toolkit.fluxcd.io/ocirepository/v1beta2"
  helmrepository "source.toolkit.fluxcd.io/helmrepository/v1beta2"
)

applicationDir: string & strings.MinRunes(1) @tag(applicationDir)
applicationName: path.Base(applicationDir)

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
#ClusterResources: {
  [Name=!~"^(_|#)"]: {
    metadata: {
      namespace?: _|_
      name: string | *Name
      ...
    }
    ...
  }
}
// On namespaced resources, set the default namespace
#Resources: {
  _namespace: #Namespace
  [Name=!~"^(_|#)"]: {
    metadata: {
      namespace: string | *_namespace.metadata.name
      name: string | *Name
      ...
    }
    ...
  }
}

#Manifest: {
  _type: "manifest"
  namespace: #Namespace
  clusterResources: #ClusterResources
  resources: #Resources & { _namespace: namespace }
}

manifests: {
  [!~"^(_|#)"]: #Manifest
}

#Repository: {
  apiVersion: ocirepository.#OCIRepository.apiVersion
  kind: ocirepository.#OCIRepository.kind
  metadata: {
    name: "netserv-ghcr"
    namespace: fluxResources._namespace.metadata.name
  }
}

#HelmRepository: {
  apiVersion: helmrepository.#HelmRepository.apiVersion
  kind: helmrepository.#HelmRepository.kind
  metadata: {
    name: "netserv-ghcr"
    namespace: fluxResources._namespace.metadata.name
  }
}

fluxResources: #Resources & {
  _namespace: #Namespace & {_name: "flux-system"}
  appKustomization: kustomization.#Kustomization & {
    metadata: name: applicationName
    spec: {
      path: "./\(applicationDir)/manifests"
      interval: _ | *"10m0s"
      prune: _ | *true
      sourceRef: #Ref & {_obj: #Repository}
    }
  }
}
