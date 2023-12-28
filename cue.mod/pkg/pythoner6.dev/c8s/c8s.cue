package c8s

import (
  "encoding/yaml"

  corev1 "k8s.io/api/core/v1"
  helmrepository "source.toolkit.fluxcd.io/helmrepository/v1beta2"
  ocirepository "source.toolkit.fluxcd.io/ocirepository/v1beta2"
  kustomizationv1 "kustomize.toolkit.fluxcd.io/kustomization/v1"
)


#Ref: {
  #obj: {
    apiVersion: string
    kind: string
    metadata: {
      name: string
      namespace?: string
      ...
    }
    ...
  }
  apiVersion: #obj.apiVersion
  kind: #obj.kind
  if #obj.metadata.namespace != _|_ {
    namespace: #obj.metadata.namespace
  }
  name: #obj.metadata.name
}

#DepRef: {
  #obj: { 
    metadata: {
      name: string
      namespace?: string
      ...
    }
    ...
  }
  if #obj.metadata.namespace != _|_ {
    namespace: #obj.metadata.namespace
  }
  name: #obj.metadata.name
}

ChartsDef=#Charts: {
  #in: string
  #repo: #Ref.#obj
  for name, tag in yaml.Unmarshal(#in) & {[_]: string} {
    (name): {
      chart: name
      version: tag
      sourceRef: #Ref & {#obj: #repo}
    }
  }
}

#Namespace: corev1.#Namespace & {
  #name: string
  metadata: name: #name
}

#Resources: this={
  #namespace: #Namespace
  #asList: [for _, resource in this {resource}]
  [Name=!~"^[_#]"]: {
    metadata: {
      namespace: string | *#namespace.metadata.name
      name: string | *Name
      ...
    }
    ...
  }
}

#Kustomization: {
  _#appName: string
  #fullName: [if #name == "$default" {_#appName}, "\(_#appName)-\(#name)"][0]
  #name: string
  #namespace: #Namespace
  #defaultResourceNamespace: #Namespace
  #dependsOn: [...#Kustomization]
  [!~"^[_#]"]: #Resources & {#namespace: _ | *#defaultResourceNamespace}
}

#Kustomizations: this={
  #appName: string
  #defaultKustomizationNamespace: #Namespace
  #defaultResourceNamepsace: #Namespace
  [Name=!~"^[_#]"]: #Kustomization & {
    _#appName: #appName
    #name: _ | *Name
    #namespace: _ | *#defaultKustomizationNamespace
    #defaultResourceNamespace: this.#defaultResourceNamespace
  }
}


#FluxResources: #Resources & {
  #namespace: #Namespace
  #kustomizations: #Kustomizations
  #repo: string
  #appName: string
  #digests: { [string]: string }
  for kname, kustomization in #kustomizations {
    repo="repository:\(kname)": ocirepository.#OCIRepository & {
      metadata: {
        "name": kustomization.#fullName
        namespace: kustomization.#namespace.metadata.name
      }
      spec: {
        url: "oci://\(#repo)/\(metadata.name)"
        interval: string | *"24h"
      }
    }
    "kustomization:\(kname)": kustomizationv1.#Kustomization & {
      metadata: {
        "name": kustomization.#fullName
        namespace: kustomization.#namespace.metadata.name
      }
      spec: {
        path: "./"
        interval: _ | *"10m0s"
        prune: _ | *true
        sourceRef: #Ref & {#obj: repo}
        dependsOn: [for dep in kustomization.#dependsOn {name: dep.#fullName, namespace: dep.#namespace.metadata.name}]
        wait: _ | *true
      }
    }
  }
}

#Default: this={
  #appName: string
  #defaultKustomizationNamespace: #Namespace
  #defaultResourceNamespace: #Namespace
  #repo: string
  #charts: string
  #chartsRepo: helmrepository.#HelmRepository

  #Charts: ChartsDef & {
    #in: #charts
    #repo: #chartsRepo
  }

  kustomizations: #Kustomizations & {
    #appName: this.#appName
    #defaultKustomizationNamespace: this.#defaultKustomizationNamespace
    #defaultResourceNamespace: this.#defaultResourceNamespace
  }

  #fluxResources: #FluxResources & {
    #repo: this.#repo
    #kustomizations: kustomizations
    #appName: this.#appName
    #namespace: #defaultKustomizationNamespace
  }
}
