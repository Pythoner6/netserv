{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs, nixpkgs-unstable }:
    let
      system = "x86_64-linux";
      name = "netserv";
      src = ./.;
      pkgs = nixpkgs.legacyPackages.${system};
      pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      lib = pkgs.lib;

      kube-version = "v1.29.0";

      cue-nix = import ./cue.nix {inherit pkgs;};
      timoni-nix = import ./timoni.nix {inherit pkgs kube-version;};

      flux = pkgs.stdenv.mkDerivation {
        name = "flux";
        src = pkgs.fetchzip {
          url = "https://github.com/fluxcd/flux2/releases/download/v2.2.0/flux_2.2.0_linux_amd64.tar.gz";
          hash = "sha256-Qw6x2ljZtvOBXe2KiGbeEN1APDeGbWGT3/kE5JIMWNs=";
        };
        installPhase = "set -e; mkdir -p $out/bin; cp $src/flux $out/bin";
      };

      charts = {
        external-secrets = {
          drv = pkgs.fetchurl {
            url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.9.9/external-secrets-0.9.9.tgz";
            hash = "sha256-IH23aIHpWns5hOEsEsV/P4PGgr1zzkxjd/5960tLEMI=";
          };
          crd-enable-key = "installCRDs";
        };
        cert-manager = {
          drv = pkgs.fetchurl {
            url = "https://charts.jetstack.io/charts/cert-manager-v1.13.3.tgz";
            hash = "sha256-8w8+b3Mn8XHssa1gB531VjmtZGmoDzLltgZnr5UEVdU=";
          };
          crd-enable-key = "installCRDs";
        };
        rook = {
          drv = pkgs.fetchurl {
            url = "https://charts.rook.io/release/rook-ceph-v1.13.0.tgz";
            hash = "sha256-MgB79G9D8TArYezjqYFHcpNYU7vXTTL5kdREOWaiub8=";
          };
          crd-enable-key = "crds.enable";
        };
        gitea = {
          drv = pkgs.fetchurl {
            url = "https://dl.gitea.com/charts/gitea-9.6.1.tgz";
            hash = "sha256-gl+Vs6oQgZDg4TjMIy1aSkNLaIUvgXxfSzYYfiwJtlY=";
          };
        };
        ingress-nginx = {
          drv = pkgs.fetchurl {
            url = "https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-4.8.4/ingress-nginx-4.8.4.tgz";
            hash = "sha256-GBF0oU2cwCJ0eyyY8OgG2SGwBEFwTacqWoXegWyKCPs=";
          };
        };
      };

      crd-enable-key = chart: if builtins.hasAttr "crd-enable-key" chart then chart.crd-enable-key else "";
      chart-crds = builtins.mapAttrs (name: chart: timoni-nix.vendor-chart-crds name chart.drv (crd-enable-key chart)) charts;
      chart-oci-artifacts = builtins.mapAttrs (name: chart: oci-chart name chart.drv) charts;

      flux-manifests = pkgs.stdenv.mkDerivation {
        name = "flux-manifests";
        dontUnpack = true;
        buildInputs = [flux];
        installPhase = "flux install --export > $out";
      };

      flux-crds = timoni-nix.vendor-crds "flux-crds" flux-manifests;

      oci-chart = name: src: pkgs.stdenv.mkDerivation {
        inherit name src;
        dontUnpack = true;
        buildInputs = with pkgs; [ kubernetes-helm yq-go jq ];
        installPhase = "${./scripts/build_chart_oci.sh} $src";
      };

      oci-image = {name, src}: pkgs.stdenv.mkDerivation {
        inherit name;
        inherit src;
        nativeBuildInputs = [ pkgs.umoci ];
        installPhase = ''
          unpacked=$(mktemp -d)
          umoci init --layout $out
          umoci new --image $out:latest
          umoci unpack --uid-map 0:$(id -u) --gid-map 0:$(id -g) --image $out:latest "$unpacked"
          cp -a ./. "$unpacked/rootfs"
          umoci repack --image $out:latest "$unpacked"
          umoci gc --layout $out
        '';
      };
    in {
      packages.${system} = rec {
        crds = pkgs.stdenv.mkDerivation {
          name = "crds";
          unpackPhase = "true";
          configurePhase = ''
            mkdir $out
            declare -a drvs
            drvs=(${cue-nix.vendor-k8s kube-version} ${flux-crds} ${builtins.concatStringsSep " " (builtins.attrValues chart-crds)})
            IFS=$'\n'; readarray -t gen <<<"$(unset IFS; find "${"$"}{drvs[@]}" -maxdepth 1 -mindepth 1 -type d)"
            cp -a "${"$"}{gen[@]}" $out/
          '';
        };
        default = pkgs.stdenv.mkDerivation {
          name = "test";
          nativeBuildInputs = with pkgs; [ pkgs-unstable.cue jq kubernetes-helm ];
          src = ./.;
          configurePhase = ''
            mkdir cue.mod/gen/
            IFS=$'\n'; readarray -t gen <<<"$(unset IFS; find ${crds} -maxdepth 1 -mindepth 1 -type d)"
            ln -s "${"$"}{gen[@]}" cue.mod/gen/
          '';
          buildPhase = "true";
          installPhase = let 
            chartList = map (chart: chart.drv) (builtins.attrValues charts);
            join = builtins.concatStringsSep;
          in ''
            set -e
            IFS=$'\n'; readarray -t apps <<<"$(find ./apps/ -maxdepth 1 -mindepth 1 -type d -printf '%f\n')"

            chartsFile=$(mktemp)
            ${join "; " (map (c: ''echo "---" >> "$chartsFile"; helm show chart "${c}" >> "$chartsFile"'') chartList)}
            charts="$(cat $chartsFile)"
            for app in "${"$"}{apps[@]}"; do
              mkdir -p $out/$app/manifests
              echo "$out/$app/"
              declare -a injections
              injections=(
                --inject "applicationDir=$app"
                --inject "charts=$charts"
              )
              cue vet -v -c "${"$"}{injections[@]}" ./apps/$app:netserv
              injections+=(
                --inject "outputDir=$out/$app"
              )
              if [[ "$app" == "flux-components" ]]; then
                injections+=(--inject 'extraManifests={"flux-components.yaml":"${flux-manifests}"}')
              fi
              cue cmd -v "${"$"}{injections[@]}" synth ./apps/$app:netserv
            done
          '';
        };
        oci = oci-image {
          name = "oci";
          src = default;
        };
        chart-oci = pkgs.stdenv.mkDerivation {
          name = "chart-oci";
          srcs = builtins.attrValues chart-oci-artifacts;
          buildInputs = [pkgs.jq];
          dontUnpack = true;
          installPhase = ''
            mkdir $out
            for oci in $srcs; do
              manifest_digest="$(jq -r '.manifests[0].digest | sub("sha256:";"")' "$oci/index.json")"
              manifest="$oci/blobs/$(jq -r '.manifests[0].digest | sub(":";"/")' "$oci/index.json")"
              config="$oci/blobs/$(jq -r '.config.digest | sub(":";"/")' "$manifest")"
              name="$(jq -r '.name' "$config")"
              mkdir "$out/$name"
              cp -a "$oci/" "$out/$name/$manifest_digest"
            done
          '';
        };
      };
      devShells.${system} = {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [ pkgs-unstable.cue pkgs-unstable.timoni postgresql jq nodejs nodePackages.npm typescript kubernetes-helm fluxcd umoci skopeo weave-gitops yq-go go xxd ];
        };
        push = pkgs.mkShell {
          buildInputs = with pkgs; [ skopeo ];
        };
        helm = pkgs.mkShell {
          buildInputs = with pkgs; [ kubernetes-helm ];
        };
      };
    };
}
