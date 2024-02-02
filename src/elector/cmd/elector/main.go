package main

import (
  "context"
  "os"
  "log"
  "syscall"
  "fmt"
  "time"
  "net/http"
  "os/signal"
  le "k8s.io/client-go/tools/leaderelection"
  rl "k8s.io/client-go/tools/leaderelection/resourcelock"
  "k8s.io/apimachinery/pkg/types"
  "k8s.io/client-go/kubernetes"
  discoveryv1client "k8s.io/client-go/kubernetes/typed/discovery/v1"
  discoveryv1app "k8s.io/client-go/applyconfigurations/discovery/v1"
  discoveryv1 "k8s.io/api/discovery/v1"
  corev1app "k8s.io/client-go/applyconfigurations/core/v1"
  corev1 "k8s.io/api/core/v1"
  metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
  "k8s.io/client-go/rest"
)

type Callbacks struct {
  PodName string
  PodUID string
  PodIP string
  NodeName string
  ServiceName string
  Namespace string
  EndpointSlices discoveryv1client.EndpointSliceInterface
}

func (c *Callbacks) OnStartedLeading(ctx context.Context) {
  log.Println(fmt.Sprintf("Started leading"))
  apply := discoveryv1app.EndpointSlice(c.ServiceName, c.Namespace).
    WithLabels(map[string]string{"kubernetes.io/service-name": c.ServiceName}).
    WithAddressType(discoveryv1.AddressTypeIPv4).
    WithPorts(discoveryv1app.EndpointPort().
      WithName("ldaps").
      WithProtocol(corev1.ProtocolTCP).
      WithPort(636)).
    WithEndpoints(discoveryv1app.Endpoint().
      WithAddresses(c.PodIP).
      WithNodeName(c.NodeName).
      WithConditions(discoveryv1app.EndpointConditions().
        WithReady(true).
        WithServing(true).
        WithTerminating(false)).
      WithTargetRef(corev1app.ObjectReference().
        WithKind("Pod").
        WithName(c.PodName).
        WithNamespace(c.Namespace).
        WithUID(types.UID(c.PodUID))))
  ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
  defer cancel()
  c.EndpointSlices.Apply(ctx, apply, metav1.ApplyOptions{FieldManager: "openldap-leader"})
  log.Println(fmt.Sprintf("Updated EndpointSlice"))
}

func (c *Callbacks) OnStoppedLeading() {
  log.Println(fmt.Sprintf("Stopped leading"))
}

func (c *Callbacks) OnNewLeader(identity string) {
  log.Println(fmt.Sprintf("New leader: %s", identity))
}

type Handler func(http.ResponseWriter, *http.Request)

func (h Handler) ServeHTTP(w http.ResponseWriter, req *http.Request) {
  h(w, req)
}

func main() {
  podName := os.Getenv("POD_NAME")
  podUID := os.Getenv("POD_UID")
  podIP := os.Getenv("POD_IP")
  namespace := os.Getenv("NAMESPACE")
  nodeName := os.Getenv("NODE_NAME")
  serviceName := os.Getenv("SERVICE_NAME")

  lockType  := rl.LeasesResourceLock
  config, err := rest.InClusterConfig()
  if err != nil {
    panic(err)
  }
  client := kubernetes.NewForConfigOrDie(config)
  lock, err := rl.New(lockType, namespace, serviceName, client.CoreV1(), client.CoordinationV1(), rl.ResourceLockConfig{
    Identity: podName,
  })
  if err != nil {
    panic(err)
  }

  callbacks := Callbacks{
    PodName: podName,
    PodUID: podUID,
    PodIP: podIP,
    NodeName: nodeName,
    ServiceName: serviceName,
    Namespace: namespace,
    EndpointSlices: client.DiscoveryV1().EndpointSlices(namespace),
  }

  elector, err := le.NewLeaderElector(le.LeaderElectionConfig{
    Lock: lock,
    LeaseDuration: 15 * time.Second,
    RenewDeadline: 10 * time.Second,
    RetryPeriod: 2 * time.Second,
    ReleaseOnCancel: true,
    Callbacks: le.LeaderCallbacks{
      OnStartedLeading: callbacks.OnStartedLeading,
      OnStoppedLeading: callbacks.OnStoppedLeading,
      OnNewLeader: callbacks.OnNewLeader,
    },
  })
  if err != nil {
    panic(err)
  }

  ctx, cancel := context.WithCancel(context.Background())
  defer cancel()

  canceled := false

  go func() {
    for !canceled {
      elector.Run(ctx)
    }
  }()

  sigint := make(chan os.Signal, 1)
	signal.Notify(sigint, os.Interrupt)
  sigkill := make(chan os.Signal, 1)
	signal.Notify(sigkill, os.Kill)
  sigterm := make(chan os.Signal, 1)
	signal.Notify(sigterm, syscall.SIGTERM)

  done := make(chan os.Signal, 1)

  go func() {
    http.ListenAndServe("0.0.0.0:80", Handler(func(w http.ResponseWriter, req *http.Request) {
      log.Println("Stopping leader election", req)
      close(done)
      w.WriteHeader(http.StatusNoContent)
      _, _ = w.Write([]byte{})
    }))
  }()

  defer func() { log.Println("Shutting down") }()

  select {
  case <-sigint:
    return
  case <-sigkill:
    return
  case <-sigterm:
    return
  case <-done:
    canceled = true
    cancel()
  }

  for {
    select {
    case <-sigint:
      return
    case <-sigkill:
      return
    case <-sigterm:
      return
    }
  }
}
