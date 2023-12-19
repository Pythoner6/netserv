package main

import (
  _ "crypto/sha256"
  "encoding/json"
  "gopkg.in/yaml.v3"
  "log"
  "fmt"
  "io"
  "path"
  "path/filepath"
  "os"
  "os/exec"
  "io/fs"
  "strings"
  "bufio"

  "github.com/gowebpki/jcs"
  ociv1 "github.com/opencontainers/image-spec/specs-go/v1"
  digest "github.com/opencontainers/go-digest"
  oci "github.com/opencontainers/image-spec/specs-go"
  "helm.sh/helm/v3/pkg/chart/loader"
  "helm.sh/helm/v3/pkg/chart"
  "helm.sh/helm/v3/pkg/action"
  "helm.sh/helm/v3/pkg/chartutil"
)

const (
  MediaTypeHelmConfig       = "application/vnd.cncf.helm.config.v1+json"
  MediaTypeHelmChartContent = "application/vnd.cncf.helm.chart.content.v1.tar+gzip"

  RookObjectBucketCRDName   = "objectbuckets.objectbucket.io"

  CueModDir                 = "cue.mod"
  CueGeneratedFilesDir      = "gen"
  TimoniBinaryName          = "timoni"

  DirectoryPermissions      = 0777
  FilePermissions           = 0644
)

func fileDigest(path string) (digest.Digest, error) {
  f, err := os.Open(path)
  if err != nil { return "", err }
  defer f.Close()

  return digest.FromReader(f)
}

func marshalCanonical(obj any) ([]byte, error) {
  data, err := json.Marshal(obj)
  if err != nil { return nil, err }

  data, err = jcs.Transform(data)
  if err != nil { return nil, err }

  return data, nil
}

func bytesDescriptor(data []byte, mediaType string) ociv1.Descriptor {
  return ociv1.Descriptor{
    MediaType: mediaType,
    Digest: digest.FromBytes(data),
    Size: int64(len(data)),
  }
}

func descriptorForArchive(chartArchive string) (ociv1.Descriptor, error) {
  chartDigest, err := fileDigest(chartArchive)
  if err != nil { return ociv1.Descriptor{}, err }

  chartStat, err := os.Stat(chartArchive)
  if err != nil { return ociv1.Descriptor{}, err }

  return ociv1.Descriptor{
    MediaType: MediaTypeHelmChartContent,
    Digest: chartDigest,
    Size: chartStat.Size(),
  }, nil
}

func extractConfigFromArchive(chart *chart.Chart) ([]byte, error) {
  config, err := marshalCanonical(chart.Metadata)
  if err != nil { return nil, err }

  return config, nil
}

func generateManifest(config ociv1.Descriptor, chart ociv1.Descriptor) ([]byte, error) {
  manifest := ociv1.Manifest{
    Versioned: oci.Versioned{SchemaVersion: 2},
    MediaType: ociv1.MediaTypeImageManifest,
    Config: config,
    Layers: []ociv1.Descriptor{chart},
  }

  data, err := marshalCanonical(manifest)
  if err != nil { return nil, err }

  return data, nil
}

func generateIndex(manifest ociv1.Descriptor) ([]byte, error) {
  index := ociv1.Index{
    Versioned: oci.Versioned{SchemaVersion: 2},
    Manifests: []ociv1.Descriptor{manifest},
  }

  data, err := marshalCanonical(index)
  if err != nil { return nil, err }

  return data, nil
}

func generateOCILayout() ([]byte, error) {
  layout := ociv1.ImageLayout{ Version: ociv1.ImageLayoutVersion }
  data, err := marshalCanonical(layout)
  if err != nil { return nil, err }

  return data, nil
}

type blobWriter struct {
  outDir          string
  createdBlobDirs map[string]bool
}

func newBlobWriter(outDir string) blobWriter {
  return blobWriter{ outDir: outDir, createdBlobDirs: make(map[string]bool) }
}

func (writer blobWriter) ensureAlgDir(alg string) error {
  blobsPath := path.Join(writer.outDir, ociv1.ImageBlobsDir, alg)
  if _, exists := writer.createdBlobDirs[alg]; !exists {
    err := os.MkdirAll(blobsPath, DirectoryPermissions)
    if err != nil {
      return err
    }
    writer.createdBlobDirs[alg] = true;
  }
  return nil
}

func (writer blobWriter) pathForDescriptor(descriptor ociv1.Descriptor) string {
  return path.Join(writer.outDir, ociv1.ImageBlobsDir, string(descriptor.Digest.Algorithm()), descriptor.Digest.Hex())
}

func (writer blobWriter) writeBlob(content []byte, descriptor ociv1.Descriptor) error {
  writer.ensureAlgDir(string(descriptor.Digest.Algorithm()))
  return os.WriteFile(writer.pathForDescriptor(descriptor), content, FilePermissions)
}

func (writer blobWriter) copyFile(src string, descriptor ociv1.Descriptor) error {
  writer.ensureAlgDir(string(descriptor.Digest.Algorithm()))
  dst := writer.pathForDescriptor(descriptor)

  srcStat, err := os.Stat(src)
  if err != nil {
          return err
  }

  if !srcStat.Mode().IsRegular() {
          return fmt.Errorf("%s is not a regular file", src)
  }

  source, err := os.Open(src)
  if err != nil {
          return err
  }
  defer source.Close()

  destination, err := os.Create(dst)
  if err != nil {
          return err
  }
  defer destination.Close()
  _, err = io.Copy(destination, source)
  return err
}

func WriteChartOCI(chartArchive, chartsDir string) error {
  chart, err := loader.LoadFile(chartArchive)
  if err != nil { return err }
  err = chart.Validate()
  if err != nil { return err }

  outDir := path.Join(chartsDir, chart.Metadata.Name)
  err = os.Mkdir(outDir, DirectoryPermissions)
  if err != nil { return err }

  archiveDescriptor, err := descriptorForArchive(chartArchive)
  if err != nil { return err }

  config, err := extractConfigFromArchive(chart)
  if err != nil { return err }
  configDescriptor := bytesDescriptor(config, MediaTypeHelmConfig)

  manifest, err := generateManifest(configDescriptor, archiveDescriptor)
  if err != nil { return err }
  manifestDescriptor := bytesDescriptor(manifest, ociv1.MediaTypeImageManifest)

  index, err := generateIndex(manifestDescriptor)
  if err != nil { return err }

  layout, err := generateOCILayout()
  if err != nil { return err }

  writer := newBlobWriter(outDir)
  err = writer.copyFile(chartArchive, archiveDescriptor)
  if err != nil { return err }
  err = writer.writeBlob(config, configDescriptor)
  if err != nil { return err }
  err = os.WriteFile(path.Join(outDir, ociv1.ImageIndexFile), index, FilePermissions)
  if err != nil { return err }
  err = os.WriteFile(path.Join(outDir, ociv1.ImageLayoutFile), layout, FilePermissions)
  if err != nil { return err }
  err = writer.writeBlob(manifest, manifestDescriptor)
  if err != nil { return err }

  return err
}

type ChartAndDigest struct {
  Metadata *chart.Metadata
  Digest digest.Digest
}

func ChartMetadataFromOCI(indexPath string) (ChartAndDigest, error) {
  readBlob := func(d digest.Digest) ([]byte, error) {
    return os.ReadFile(path.Join(
      path.Dir(indexPath), ociv1.ImageBlobsDir, string(d.Algorithm()), d.Hex(),
    ))
  }
  // Read and parse index.json
  indexBytes, err := os.ReadFile(indexPath)
  if err != nil { return ChartAndDigest{}, err }
  var index ociv1.Index
  err = json.Unmarshal(indexBytes, &index)
  if err != nil { return ChartAndDigest{}, err }
  if len(index.Manifests) > 1 {
    return ChartAndDigest{}, fmt.Errorf("container %s contains more than one manifest", indexPath)
  } else if len(index.Manifests) < 1 {
    return ChartAndDigest{}, fmt.Errorf("container %s contains no manifests", indexPath)
  }
  if index.Manifests[0].MediaType != ociv1.MediaTypeImageManifest { 
    return ChartAndDigest{}, fmt.Errorf("index: expected manifest media type `%s`, found `%s` instead", index.Manifests[0].MediaType, ociv1.MediaTypeImageManifest) 
  }
  // Read and parse manifest blob
  manifestBytes, err := readBlob(index.Manifests[0].Digest)
  if err != nil { return ChartAndDigest{}, err }
  var manifest ociv1.Manifest
  err = json.Unmarshal(manifestBytes, &manifest)
  if err != nil { return ChartAndDigest{}, err }
  if manifest.Config.MediaType != MediaTypeHelmConfig { 
    return ChartAndDigest{}, fmt.Errorf("manifest: expected config media type `%s`, found `%s` instead", MediaTypeHelmConfig, manifest.Config.MediaType)
  }
  // Read and parse config blob
  configBytes, err := readBlob(manifest.Config.Digest)
  var config chart.Metadata
  err = json.Unmarshal(configBytes, &config)
  if err != nil { return ChartAndDigest{}, err }
  err = config.Validate()
  if err != nil { return ChartAndDigest{}, err }

  return ChartAndDigest{
    Metadata: &config,
    Digest:   index.Manifests[0].Digest,
  }, nil
}

func GetChartDigests(chartsDir string) (map[string]string, error) {
  chartDigests := make(map[string]string)
  err := filepath.WalkDir(chartsDir, func(path string, entry fs.DirEntry, err error) error {
    if err != nil { return err }
    depth := strings.Count(strings.Replace(path, chartsDir, "", 1), string(os.PathSeparator))
    if entry.IsDir() && depth >= 2 {
      return fs.SkipDir
    } else if !entry.IsDir() && depth == 2 && entry.Name() == "index.json" {
      chart, err := ChartMetadataFromOCI(path)
      if err != nil { return err }
      if existingDigest, exists := chartDigests[chart.Metadata.Name]; exists {
        return fmt.Errorf("multiple digests found for chart %s: %s, %s", chart.Metadata.Name, existingDigest, chart.Digest)
      }
      chartDigests[chart.Metadata.Name] = string(chart.Digest)
    }
    return nil
  })
  return chartDigests, err
}

func fixRookObjectBucketCRD(doc map[string]any) {
  obj, ok := doc["metadata"].(map[string]any)
  if !ok { return }
  if obj["name"] != RookObjectBucketCRDName { return }

  obj, _ = doc["spec"].(map[string]any)
  versions, ok := obj["versions"].([]any)
  if !ok { return }
  for i, _ := range versions {
    obj, _ = versions[i].(map[string]any)
    obj, _ = obj["schema"].(map[string]any)
    obj, _ = obj["openAPIV3Schema"].(map[string]any)
    obj, _ = obj["properties"].(map[string]any)
    obj, _ = obj["spec"].(map[string]any)
    obj, _ = obj["properties"].(map[string]any)
    _, ok = obj["authentication"].(map[string]any)
    if !ok { continue }
    delete(obj, "authentication")
  }
}

func TemplateCRDs(chartArchive string, values map[string]any, kubeVersion string, writer io.Writer) error {
  chart, err := loader.LoadFile(chartArchive)
  if err != nil { return err }
  err = chart.Validate()
  if err != nil { return err }

  renderer := action.NewInstall(&action.Configuration{})
  renderer.ClientOnly = true
  renderer.DryRun = true
  renderer.IncludeCRDs = true
  renderer.ReleaseName = chart.Metadata.Name
  renderer.KubeVersion, err = chartutil.ParseKubeVersion(kubeVersion)
  if err != nil { return err }

  rel, err := renderer.Run(chart, values)
  if err != nil { return err }

  decoder := yaml.NewDecoder(strings.NewReader(rel.Manifest))
  encoder := yaml.NewEncoder(writer)
  defer encoder.Close()

  for {
    var doc map[string]any
    err := decoder.Decode(&doc)
    if err == io.EOF {
      break
    } else if err != nil {
      return err
    }

    if doc["kind"] == "CustomResourceDefinition" {
      fixRookObjectBucketCRD(doc)
      encoder.Encode(doc)
    }
  }

  return nil
}

func GenerateCueDefinitions(chartArchive string, values map[string]any, kubeVersion, outPath string) error {
  file, err := os.CreateTemp("", "")
  defer func() {
    file.Close()
    os.Remove(file.Name())
  }()
  if err != nil { return err }

  err = TemplateCRDs(chartArchive, values, kubeVersion, file)
  if err != nil { return err }

  err = os.MkdirAll(path.Join(outPath, CueModDir, CueGeneratedFilesDir), DirectoryPermissions)
  if err != nil { return err }

  timoni, err := exec.LookPath(TimoniBinaryName)
  if err != nil { return err }
  cmd := exec.Command(timoni, "mod", "vendor", "crd", "-f", file.Name())
  cmd.Dir = outPath
  return cmd.Run()
}

type GenerateCueInput struct {
  Values      map[string]any `json:"values"`
  KubeVersion string         `json:"kubeVersion"`
}

func main() {
  outDir := os.Getenv("out")
  src := os.Getenv("src")

  var input GenerateCueInput
  err := json.NewDecoder(bufio.NewReader(os.Stdin)).Decode(&input)

  err = GenerateCueDefinitions(src, input.Values, input.KubeVersion, outDir)
  if err != nil {
    log.Println("ERROR:", err)
    os.Exit(1)
  }

  /*
  err := WriteChartOCI("rook.tgz", "./charts")
  if err != nil {
    log.Println("ERROR:", err)
    return
  }

  chartDigests, err := GetChartDigests("./charts")
  if err != nil {
    log.Println("ERROR:", err)
    return
  }

  data, err := json.Marshal(chartDigests)
  if err != nil {
    log.Println("ERROR:", err)
    return
  }

  log.Println(string(data))
  */
}
