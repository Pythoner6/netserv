package resources

manifests: "test.yaml": {
  namespace: #Namespace & {_name: "test"}
  resources: {
    ns: namespace
  }
}
