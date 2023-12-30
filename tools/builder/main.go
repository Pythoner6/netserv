package main

import (
  "crypto/sha256"
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
  "slices"
  "cmp"
  "archive/tar"
  "compress/gzip"
  "bytes"
  //"bufio"

  "github.com/gowebpki/jcs"
  ociv1 "github.com/opencontainers/image-spec/specs-go/v1"
  digest "github.com/opencontainers/go-digest"
  oci "github.com/opencontainers/image-spec/specs-go"
  "helm.sh/helm/v3/pkg/chart/loader"
  "helm.sh/helm/v3/pkg/chart"
  "helm.sh/helm/v3/pkg/action"
  "helm.sh/helm/v3/pkg/chartutil"
  "cuelang.org/go/cue/load"
  "cuelang.org/go/cue"
  //"cuelang.org/go/cue/errors"
  "cuelang.org/go/cue/cuecontext"
  cueyaml "cuelang.org/go/encoding/yaml"
  //cuejson "cuelang.org/go/encoding/json"
  //"cuelang.org/go/encoding/gocode/gocodec"
  //"cuelang.org/go/cue/build"
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

func bytesDescriptorWithName(data []byte, mediaType, name string) ociv1.Descriptor {
  return ociv1.Descriptor{
    MediaType: mediaType,
    Digest: digest.FromBytes(data),
    Size: int64(len(data)),
    Annotations: map[string]string{
      ociv1.AnnotationRefName: name,
    },
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

func configForContent(content []byte) ([]byte, error) {
  h := sha256.New()
  _, err := io.Copy(h, bytes.NewReader(content))
  if err != nil { return nil, err }

  config := ociv1.Image{
    RootFS: ociv1.RootFS{
      Type: "layers",
      DiffIDs: []digest.Digest{digest.NewDigest(digest.SHA256, h)},
    },
  }

  configJson, err := marshalCanonical(config)
  if err != nil { return nil, err }

  return configJson, nil
}

func WriteOCI(outDir string, name string, content []byte) error {
  var buf bytes.Buffer
  gzipWriter := gzip.NewWriter(&buf)
  _, err := io.Copy(gzipWriter, bytes.NewReader(content))
  gzipWriter.Close()
  if err != nil { return err }

  contentDescriptor := bytesDescriptor(buf.Bytes(), ociv1.MediaTypeImageLayerGzip)

  config, err := configForContent(content)
  if err != nil { return err }
  configDescriptor := bytesDescriptor(config, ociv1.MediaTypeImageConfig)

  manifest, err := generateManifest(configDescriptor, contentDescriptor)
  if err != nil { return err }
  manifestDescriptor := bytesDescriptorWithName(manifest, ociv1.MediaTypeImageManifest, name)

  index, err := generateIndex(manifestDescriptor)
  if err != nil { return err }

  layout, err := generateOCILayout()
  if err != nil { return err }

  writer := newBlobWriter(outDir)
  err = writer.writeBlob(buf.Bytes(), contentDescriptor)
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

//type Kustomization struct {
//  Name      string     `cue:"_name"`
//  Manifests []Manifest `cue:""`
//}

type Manifest struct {
  Name    string
  Content io.Reader
  Size    int64
}

func generateKustomizationTarData(kustomization cue.Value, extraManifests map[string]string, writer io.Writer) error {
  tarWriter := tar.NewWriter(writer)
  defer tarWriter.Close()

  manifests, err := kustomization.Fields()
  var files []Manifest
  if err != nil { return err }
  for manifests.Next() {
    manifestName := manifests.Selector().Unquoted()
    if err != nil { return err }
    resources := manifests.Value().LookupPath(cue.MakePath(cue.Def("#asList")))
    resourceList, err := resources.List()
    if err != nil { return err }
    data, err := cueyaml.EncodeStream(resourceList)
    if err != nil { return err }
    files = append(files, Manifest{Name: manifestName, Content: bytes.NewReader(data), Size: int64(len(data))})
  }
  for output, input := range extraManifests {
    file, err := os.Open(input)
    if err != nil { return err }
    stat, err := file.Stat()
    if err != nil { return err }
    files = append(files, Manifest{Name: output, Content: file, Size: stat.Size()})
  }
  slices.SortFunc(files, func(a,b Manifest) int { return cmp.Compare(a.Name, b.Name) })
  for _, manifest := range files {
    err = tarWriter.WriteHeader(&tar.Header{
      Size: manifest.Size,
      Mode: 0644,
      Name: manifest.Name + ".yaml",
      Format: tar.FormatPAX,
    })
    if err != nil { return err }
    written, err := io.Copy(tarWriter, manifest.Content)
    if err != nil { return err }
    if written != manifest.Size {
      return fmt.Errorf("wrong amount of bytes written")
    }
  }

  return nil
}

func Synth(pkgs, tags []string, extraManifests map[string]map[string]string, outDir string) error {
  cfg := load.Config{
    Tags: tags,
  }

  ctx := cuecontext.New()
  values, err := ctx.BuildInstances(load.Instances(pkgs, &cfg))
  if err != nil { return err }

  for i := range values {
    err = values[i].Validate(cue.Concrete(true), cue.Definitions(true), cue.Final())
    if err != nil { return err }
    kustomizationsValue := values[i].LookupPath(cue.MakePath(cue.Str("kustomizations")))
    kustomizations, err := kustomizationsValue.Fields()
    if err != nil { return err }

    for kustomizations.Next() {
      var buf bytes.Buffer

      kustomizationFullName, err := kustomizations.Value().LookupPath(cue.MakePath(cue.Def("#fullName"))).String()
      if err != nil { return err }

      kustomizationName, err := kustomizations.Value().LookupPath(cue.MakePath(cue.Def("#name"))).String()
      if err != nil { return err }

      extra, ok := extraManifests[kustomizationName]
      if !ok { 
        extra = map[string]string{}
      }

      generateKustomizationTarData(kustomizations.Value(), extra, &buf)


      WriteOCI(path.Join(outDir, kustomizationFullName), kustomizationFullName, buf.Bytes())
    }
    if err != nil { panic(err) }
  }
  
  return nil
}

type SynthInput struct {
  Path           string   `json:"path"`
  ChartIndex     string   `json:"chartIndex"`
  CuePackageName string   `json:"cuePackageName"`
  CueDefinitions []string `json:"cueDefinitions"`
  ExtraManifests map[string]map[string]string `json:"extraManifests"`
  Apps           []string `json:"apps"`
}

func main() {
  bytes, err := io.ReadAll(os.Stdin)
  if err != nil { panic(err) }

  log.Println(string(bytes))

  var input SynthInput
  err = json.Unmarshal(bytes, &input)
  if err != nil { panic(err) }

  index, err := os.Open(input.ChartIndex)
  if err != nil { panic(err) }
  charts, err := io.ReadAll(index)
  if err != nil { panic(err) }
  tags := []string{
    "charts=" + string(charts),
  }

  digests := make(map[string]string)
  for _, app := range input.Apps {
    entries, err := os.ReadDir(app)
    if err != nil { panic(err) }
    for _, entry := range entries {
      if !entry.IsDir() {
        continue
      }

      indexFile, err := os.Open(path.Join(app, entry.Name(), "index.json"))
      if err != nil { panic(err) }
      indexJson, err := io.ReadAll(indexFile)
      if err != nil { panic(err) }
      var index ociv1.Index
      err = json.Unmarshal(indexJson, &index)
      if err != nil { panic(err) }
      if len(index.Manifests) != 1 {
        panic("Expected exactly one manifest in index")
      }
      digests[entry.Name()] = index.Manifests[0].Digest.Encoded()
    }
  }
  
  if len(digests) > 0 {
    digestsJson, err := json.Marshal(digests)
    if err != nil { panic(err) }
    tags = append(tags, "digests=" + string(digestsJson))
  }

  os.MkdirAll("./cue.mod/gen", DirectoryPermissions)

  for _, def := range input.CueDefinitions {
    entries, err := os.ReadDir(def)
    if err != nil { panic(err) }
    for _, entry := range entries {
      if !entry.IsDir() {
        continue
      }

      err = os.Symlink(path.Join(def, entry.Name()), path.Join("./cue.mod/gen", entry.Name()))
      if err != nil { panic(err) }
    }
  }

  err = Synth([]string{"./" + input.Path + ":" + input.CuePackageName}, tags, input.ExtraManifests, os.Getenv("out"))
  if err != nil { panic(err) }

  /*
  outDir := os.Getenv("out")
  src := os.Getenv("src")

  var input GenerateCueInput
  err := json.NewDecoder(bufio.NewReader(os.Stdin)).Decode(&input)

  err = GenerateCueDefinitions(src, input.Values, input.KubeVersion, outDir)
  if err != nil {
    log.Println("ERROR:", err)
    os.Exit(1)
  }
  */

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
