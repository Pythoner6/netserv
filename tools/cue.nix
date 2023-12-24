{pkgs, kubeVersion}: let
  versions = {
    "v1.29.0" = "sha256-M0zdXmTfyykNtzkQu1D/+DWAoeOWOpLS7Qy6UFT6/Ns=";
  };
  serialize = data: builtins.toJSON (builtins.toJSON data);
  getOpt = attrset: attr: default: if attrset ? ${attr} then attrset.${attr} else default;
  lib = pkgs.lib;

  oci = import ./oci.nix {inherit pkgs;};

  fromK8s = pkgs.buildGoModule {
    name = "vendor-k8s";
    src = ./k8s-defs + "/${kubeVersion}";
    nativeBuildInputs = with pkgs; [ cue ];
    vendorHash = versions."${kubeVersion}";
    buildPhase = ''
      cue get go k8s.io/api/...
      cue get go k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1
    '';
    installPhase = ''
      mkdir "$out"
      cp -r cue.mod/gen/. "$out"
    '';
  };

  fromChart = name: chart: pkgs.stdenv.mkDerivation {
    inherit name;
    inherit (chart) src;
    dontUnpack = true;
    nativeBuildInputs = with pkgs; [ kubernetes-helm timoni yq-go ];
    installPhase = "${./scripts/vendor_chart_crds.sh} ${builtins.toJSON (builtins.toJSON (if chart ? "crdValues" then chart.crdValues else {}))} ${kubeVersion}";
  };

  #filterSources = src: lib.sources.sourceByRegex src (let
  #  f = remaining: transformed: let
  #    numRemaining = builtins.length remaining;
  #  in if numRemaining == 0 then transformed else let
  #    prefix = lib.lists.sublist 0 (numRemaining - 1) remaining;
  #    regex = "^" + (lib.strings.concatStringsSep "/" (prefix ++ [(lib.lists.last remaining) ''[^/]*$'']));
  #  in f prefix ([regex] ++ transformed);
  #  components = lib.path.subpath.components appPath;
  #in f components [''^[^/]*$'']);

  synthApp = { name, src, appPath, chartIndex, cuePackageName, extraManifests, cueDefinitions }:
  let
    inputs = {
      inherit chartIndex cuePackageName cueDefinitions extraManifests;
      path = appPath;
    };
  in pkgs.stdenv.mkDerivation {
    inherit name;
    src = src;
    nativeBuildInputs = with pkgs; [ cue jq ];
    installPhase = "${./scripts/synth.sh} <<< ${serialize inputs}";
  };
in rec {
  #builder = pkgs.buildGoModule {
  #  name = "builder";
  #  src = ./builder;
  #  vendorHash = "sha256-Tq/zgsOdXms916ms1+Wa0MweKa0P7dn/0g0mvaGJV2Y=";
  #};

  fromCrds = name: src: pkgs.stdenv.mkDerivation {
    inherit name src;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.kubernetes-helm pkgs.timoni pkgs.yq-go ];
    installPhase = ''
      mkdir "$out"
      mkdir cue.mod
      timoni mod vendor crd -f "$src"
      cp -r cue.mod/gen/. "$out"
    '';
  };

  charts = let
    flattenMap = f: attrset: builtins.attrValues (builtins.mapAttrs f attrset);
  in charts: rec {
    cueDefinitions = flattenMap (name: chart: fromChart name chart) charts;
    chartArtifacts = flattenMap (name: chart: oci.fromChart name chart.src) charts;
    chartIndex = pkgs.stdenv.mkDerivation {
      name = "chart-index";
      dontUnpack = true;
      nativeBuildInputs = [ pkgs.jq ];
      installPhase = "${./scripts/build_chart_index.sh} <<< ${serialize chartArtifacts}";
    };
  };

  synth = { name, src, appsSubdir ? ".", charts, cuePackageName ? name, extraManifests, extraDefinitions } @ args: 
  let
    apps = builtins.mapAttrs (appName: v: synthApp {
      inherit src cuePackageName;
      name = appName;
      appPath = "${appsSubdir}/${appName}";
      cueDefinitions = [fromK8s] ++ extraDefinitions ++ charts.cueDefinitions;
      chartIndex = charts.chartIndex;
      extraManifests = getOpt args.extraManifests appName null;
    }) (pkgs.lib.attrsets.filterAttrs (n: v: v == "directory" && n != "cue.mod") (builtins.readDir "${src}/${appsSubdir}"));
  in pkgs.stdenv.mkDerivation {
    inherit name;
    nativeBuildInputs = [ pkgs.jq ];
    dontUnpack = true;
    installPhase = ''
      set -euxo pipefail
      mkdir "$out"
      declare -A apps="($(jq -r 'to_entries | map(.key, .value | tostring) | @sh' <<< ${serialize apps}))"
      for app in "''${!apps[@]}"; do
        cp -r "''${apps["$app"]}/." "$out"
      done
      set +x
    '';
  };

  images = { name, src, charts } @ args: let
  in pkgs.stdenv.mkDerivation {
    inherit name;
    src = oci.image {
      inherit name;
      inherit (args) src;
    };
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.jq ];
    installPhase = ''
      declare -a charts="($(jq -r '@sh' <<< ${serialize charts.chartArtifacts}))"
      mkdir -p "$out/charts"
      declare -p charts
      for chart in "''${charts[@]}"; do
        cp -r "$chart" "$out/charts/"
      done
      cp -r "$src" "$out/apps"
    '';
  };
}
