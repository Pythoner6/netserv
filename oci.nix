{pkgs}: let
  serialize = data: builtins.toJSON (builtins.toJSON data);
in {
  fromChart = name: src: pkgs.stdenv.mkDerivation {
    inherit name src;
    dontUnpack = true;
    buildInputs = with pkgs; [ kubernetes-helm yq-go jq ];
    installPhase = "${./tools/scripts/build_chart_oci.sh}";
  };

  image = {name, src}: pkgs.stdenv.mkDerivation {
    inherit name;
    inherit src;
    nativeBuildInputs = [ pkgs.jq ];
    #nativeBuildInputs = [ pkgs.umoci ];
    #installPhase = ''
    #  unpacked="$(mktemp -d)"
    #  umoci init --layout "$out"
    #  umoci new --image "$out"
    #  umoci unpack --uid-map 0:$(id -u) --gid-map 0:$(id -g) --image "$out" "$unpacked"
    #  cp -a ./. "$unpacked/rootfs"
    #  find "$unpacked" -exec touch -d '1970-01-01T00:00:01Z' {} +
    #  umoci repack --no-history --image "$out" "$unpacked"
    #  umoci gc --layout "$out"
    #'';
    installPhase = "${./tools/scripts/build_manifest_oci.sh}";
  };
}
