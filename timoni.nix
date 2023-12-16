{pkgs, kube-version}: {
  vendor-crds = name: src: pkgs.stdenv.mkDerivation {
    inherit name src;
    dontUnpack = true;
    buildInputs = [ pkgs.kubernetes-helm pkgs.timoni pkgs.yq-go ];
    installPhase = ''
      mkdir $out
      mkdir cue.mod
      timoni mod vendor crd -f "$src"
      cp -a cue.mod/gen/. $out
    '';
  };
  vendor-chart-crds = name: chart: key: pkgs.stdenv.mkDerivation {
    inherit name;
    src = chart;
    dontUnpack = true;
    buildInputs = with pkgs; [ kubernetes-helm timoni yq-go ];
    installPhase = "${./scripts/vendor_chart_crds.sh} ${key} ${kube-version}";
  };
}
