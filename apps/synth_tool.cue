package netserv

import (
  "tool/exec"
  "tool/file"
  "strings"
  "path"
  "list"
  "crypto/sha256"
  "encoding/hex"
  "encoding/yaml"
  "encoding/json"
)

outputDir: string & strings.MinRunes(1) @tag(outputDir)
extraManifests: string | *null @tag(extraManifests)

#FluxResourceOrdering: {
  _obj: {apiVersion: string}
  order: [
    if strings.HasPrefix(_obj.apiVersion, "source.toolkit.fluxcd.io/") {-1},
    0,
  ][0]
}

command: synth: {
  "create-manifests-dir": file.Mkdir & {
    createParents: true
    path: "\(outputDir)/manifests"
  }

  if extraManifests != null {
      for output, input in json.Unmarshal(extraManifests) {
        "copy-extra-manifest-\(hex.Encode(sha256.Sum256(output)))": exec.Run & {
          cmd: "cp \(input) \(outputDir)/manifests/\(output)"
        }
      }
  }

  "create-kustomization-yaml": file.Create & {
    filename: "\(outputDir)/kustomization.yaml"
    contents: yaml.Marshal({
      apiVersion: "kustomize.config.k8s.io/v1beta1"
      kind: "Kustomization"
      resources: [ "./flux-resources.yaml" ]
    })
  }

  "create-flux-resources-yaml": file.Create & {
    filename: "\(outputDir)/flux-resources.yaml"
    contents: yaml.MarshalStream(list.Sort([for _, r in fluxResources {r}], {
      x: _
      y: _
      less: (#FluxResourceOrdering & { _obj: x }).order < (#FluxResourceOrdering & { _obj: y }).order
    }))
  }

  for name, manifest in manifests {
    "create-file-\(hex.Encode(sha256.Sum256(name)))": file.Create & {
      filename: "\(outputDir)/manifests/\(name & path.Base(name))"
      contents: yaml.MarshalStream([
        for _, r in manifest.clusterResources {r},
        for _, r in manifest.resources {r},
      ])
    }
  }
}
