package netserv

#Config: {
  _model: string
  if _model == "m720q" {
    _installdisk: "/dev/nvme0n1"
    machine: {
      nodeLabels: ceph: "yes"
      disks: [{
        device: "/dev/nvme0n2"
        partitions: [{mountpoint: "/var/storage"}]
      }]
      network: interfaces: [{
        interface: "enp1s0"
      }]
      install: extraKernelArgs: [
        "net.ifnames=1",
        "pcie_aspm=off",
      ]
    }
  }
}
