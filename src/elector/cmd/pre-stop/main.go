package main

import (
  "bytes"
  "context"
  "log"
  "net/http"
  "os"
  "time"

  discoveryv1 "k8s.io/api/discovery/v1"
  "k8s.io/client-go/kubernetes"
  "k8s.io/client-go/rest"
  "k8s.io/client-go/tools/cache"
  "k8s.io/client-go/tools/watch"
  "k8s.io/apimachinery/pkg/fields"
  metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
  machinerywatch "k8s.io/apimachinery/pkg/watch"
)

func main() {
  namespace := os.Getenv("NAMESPACE")
  serviceName := os.Getenv("EXTERNAL_SERVICE_NAME")
  podIP := os.Getenv("POD_IP")

  client := http.Client{
    Timeout: 30 * time.Second,
  }
  _, err := client.Post("http://localhost/stop-election", "application/json", bytes.NewReader([]byte{}))
  if err != nil {
    panic(err)
  }

  config, err := rest.InClusterConfig()
  if err != nil {
    panic(err)
  }
  kclient := kubernetes.NewForConfigOrDie(config)

  condition := func(slice *discoveryv1.EndpointSlice) (bool, error) {
    log.Println(slice)
    for _, endpoint := range slice.Endpoints {
      for _, address := range endpoint.Addresses {
        log.Println("POD_IP =", podIP)
        log.Println("comparing to", address)
        if address != podIP {
          log.Println("Found other address, done!")
          return true, nil
        }
      }
    }
    return false, nil
  }

  watch.UntilWithSync(
    context.Background(), 
    cache.NewListWatchFromClient(
      kclient.DiscoveryV1().RESTClient(), 
      "endpointslices", 
      namespace, 
      fields.OneTermEqualSelector(metav1.ObjectNameField, serviceName),
    ),
    &discoveryv1.EndpointSlice{},
    func(store cache.Store) (bool, error) {
      obj, present, err := store.GetByKey(namespace + "/" + serviceName)
      if !present || err != nil{
        return false, nil
      }
      slice, ok := obj.(*discoveryv1.EndpointSlice)
      if !ok {
        return false, nil
      }
      return condition(slice) 
    },
    func(event machinerywatch.Event) (bool, error) {
      if slice, ok := event.Object.(*discoveryv1.EndpointSlice); ok {
        return condition(slice)
      } else {
        return false, nil
      }
    },
  )
}
