package netserv

import (
  "tool/exec"
  "tool/file"
  "strings"
  //"path"
  "list"
  //"crypto/sha256"
  //"encoding/hex"
  "encoding/yaml"
  //"encoding/json"
)

outputDir: string & strings.MinRunes(1) @tag(outputDir)
_appDir: "\(outputDir)/\(appName)"

#FluxResourceOrdering: {
  _obj: {apiVersion: string}
  order: [
    if strings.HasPrefix(_obj.apiVersion, "source.toolkit.fluxcd.io/") {-1},
    0,
  ][0]
}

command: synth: {
  mkAppDir: file.Mkdir & {
    createParents: true
    permissions: 0o777
    path: "\(_appDir)"
  }

  //if extraManifests != null {
  //    for output, input in json.Unmarshal(extraManifests) {
  //      "copy-extra-manifest-\(hex.Encode(sha256.Sum256(output)))": exec.Run & {
  //        $after: [mkAppDir]
  //        cmd: ["cp", input, "\(_appDir)/manifests/\(output)"]
  //      }
  //    }
  //}

  "create-kustomization-yaml": file.Append & {
    $after: [mkAppDir]
    filename: "\(_appDir)/kustomization.yaml"
    contents: yaml.Marshal({
      apiVersion: "kustomize.config.k8s.io/v1beta1"
      kind: "Kustomization"
      resources: [ "./flux-resources.yaml" ]
    })
  }

  "create-flux-resources-yaml": file.Create & {
    $after: [mkAppDir]
    filename: "\(_appDir)/flux-resources.yaml"
    contents: yaml.MarshalStream(list.Sort([for _, r in fluxResources {r}], {
      x: _, y: _
      less: (#FluxResourceOrdering & { _obj: x }).order < (#FluxResourceOrdering & { _obj: y }).order
    }))
  }

  for kustomizationName, kustomization in kustomizations {
    mkKustomizationDir=(fluxResources[kustomizationName].spec.path): file.Mkdir & {
      createParents: true
      permissions: 0o777
      path: "\(outputDir)/\(fluxResources[kustomizationName].spec.path)"
    }
    for output, input in kustomization._extraManifests {
      "\(fluxResources[kustomizationName].spec.path)/\(output)": exec.Run & {
        $after: [mkKustomizationDir]
        cmd: ["cp", input, "\(outputDir)/\(fluxResources[kustomizationName].spec.path)/\(output)"]
      }
    }
    for manifestName, manifest in kustomization {
      "\(fluxResources[kustomizationName].spec.path)/\(manifestName)": file.Create & {
        $after: [mkKustomizationDir]
        filename: "\(outputDir)/\(fluxResources[kustomizationName].spec.path)/\(manifestName)"
        contents: yaml.MarshalStream([
          for _, r in manifest.clusterResources {r},
          for _, r in manifest.resources {r},
        ])
      }
    }
  }
}
