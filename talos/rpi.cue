package netserv

#Config: { 
  _model: string
  _controlplane: bool
  if _model == "rpi" {
    _installdisk: [if _controlplane {"/dev/nvme0n1"}, "/dev/mmcblk0"][0]
    machine: {
      if !_controlplane {
        disks: [{
          device: "/dev/nvme0n1"
          partitions: [{mountpoint: "/var/storage"}]
        }]
      }
      network: interfaces: [{
        deviceSelector: driver: "bcmgenet"
      }]
    }
  }
}
