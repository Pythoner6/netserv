package netserv

#Nodes: [
  for i in [1,2,3] { #Config & {
    _address: "10.16.2.\(100 + i)"
    _controlplane: true
    _model: "rpi"
  }}
  for i in [1,2,3] { #Config & {
    _address: "10.16.2.\(200 + i)"
    _controlplane: false
    _model: "rpi"
  }}
  for i in [1,2,3] { #Config & {
    _address: "10.16.2.\(220 + i)"
    _controlplane: false
    _model: "m720q"
  }}
]
