package netserv

_talosVersion: string
_kubeVersion: "1.29.0"

#Config: {
  _address: string
  _controlplane: bool
  _model: "rpi" | "m720q"
  _endpoint: "10.16.2.10"
  _installdisk: string

  machine: {
    time: servers: ["time.cloudflare.com"]
    if !_controlplane {
      nodeLabels: #DefaultBGPPolicyLabels
    }
    network: {
      nameservers: ["192.168.1.1"]
      interfaces: [{
        dhcp: false,
        addresses: [ "\(_address)/24" ]
        routes: [{
          network: "0.0.0.0/0"
          gateway: "10.16.2.2"
        }]
        if _controlplane {
          vip: ip: _endpoint
        }
      }]
    }
    if !_controlplane {
      install: wipe: true
    }
  }
  cluster: {
    proxy: disabled: true
    network: {
      podSubnets: ["172.16.0.0/16"]
      serviceSubnets: ["172.17.0.0/16"]
      cni: name: "none"
    }
  }
}
