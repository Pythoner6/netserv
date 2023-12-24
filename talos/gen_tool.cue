package netserv

import (
  "tool/exec"
  "tool/file"
  "regexp"
  "encoding/json"
  "encoding/yaml"
)

outputDir: string | *"output" @tag(outputDir)
_talosVersion : regexp.ReplaceAll("^v", json.Unmarshal(command.gen."versions.json".contents).talos.version, "")

command: gen: {
  mkdir: file.MkdirAll & {
    path: outputDir
  }

  "versions.json": file.Read & {
    filename: "versions.json"
  }

  for node in #Nodes {
    "node-\(node._address)": exec.Run & {
      $after: [mkdir]
      _type: [if node._controlplane {"controlplane"}, "worker"][0]
      cmd: [
        "talosctl", "gen", "config", "--force", 
        "--config-patch", yaml.Marshal(node), 
        "--with-secrets", "secrets.yaml",
        "--install-image", "ghcr.io/siderolabs/installer:v\(_talosVersion)",
        "--talos-version", "v\(_talosVersion)", 
        "--kubernetes-version", _kubeVersion,
        "--install-disk", node._installdisk,
        "--output-types", _type,
        "--output", "\(outputDir)/\(_type)-\(node._address).yaml",
        "netserv", "https://\(node._endpoint):6443",
      ]
    }
  }
}
