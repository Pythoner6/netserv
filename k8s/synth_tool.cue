package netserv

import (
  "tool/exec"
  "tool/file"
  "tool/os"
  "strings"
  //"path"
  //"list"
  //"crypto/sha256"
  //"encoding/hex"
  "encoding/yaml"
  //"encoding/json"
)

outputDir: string & strings.MinRunes(1) @tag(outputDir)

#FluxResourceOrdering: {
  _obj: {apiVersion: string}
  order: [
    if strings.HasPrefix(_obj.apiVersion, "source.toolkit.fluxcd.io/") {-1},
    0,
  ][0]
}

command: synth: {
  envVars: os.Environ

  for kustomizationName, kustomization in kustomizations {
    (kustomizationName): {
      _kustomizationSubdir: "\(appName)\([if kustomizationName == "$default" {""}, "-" + kustomizationName][0])"
      kustomizationDir: file.Mkdir & {
        createParents: true
        permissions: 0o777
        path: "\(outputDir)/\(_kustomizationSubdir)"
      }
      for output, input in kustomization._extraManifests {
        "manifest:\(output)": exec.Run & {
          $after: [kustomizationDir]
          cmd: ["cp", input, "\(kustomizationDir.path)/\(output)"]
        }
      }
      for manifestName, manifest in kustomization {
        "manifest:\(manifestName)": file.Create & {
          $after: [kustomizationDir]
          filename: "\(kustomizationDir.path)/\(manifestName)"
          contents: yaml.MarshalStream([
            for _, r in manifest.clusterResources {r},
            for _, r in manifest.resources {r},
          ])
        }
      }
      oci: exec.Run & {
        $after: [
          for output, _ in kustomization._extraManifests { command.synth["manifest:\(output)"] },
          for manifestName, _ in kustomization { command.synth["manifest:\(manifestName)"] },
        ]
        cmd: ["bash", "./tools/scripts/build_manifest_oci.sh", "\(outputDir)/\(_kustomizationSubdir)"]
        env: {
          out: "\(outputDir)/oci/\(_kustomizationSubdir)"
          for k, v in envVars if k !~"^[$]" && k != "out" { 
            (k): v
          }
        }
      }
    }
  }
}
