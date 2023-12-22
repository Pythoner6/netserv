{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
  };
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      name = "netserv";
      src = ./.;
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      kubeVersion = "v1.29.0";

      cue = import ./tools/cue.nix {inherit pkgs kubeVersion;};

      flux = pkgs.stdenv.mkDerivation {
        name = "flux";
        src = pkgs.fetchzip {
          url = "https://github.com/fluxcd/flux2/releases/download/v2.2.0/flux_2.2.0_linux_amd64.tar.gz";
          hash = "sha256-Qw6x2ljZtvOBXe2KiGbeEN1APDeGbWGT3/kE5JIMWNs=";
        };
        installPhase = "set -e; mkdir -p $out/bin; cp $src/flux $out/bin";
      };

      flux-manifests = pkgs.stdenv.mkDerivation {
        name = "flux-manifests";
        dontUnpack = true;
        buildInputs = [flux];
        installPhase = "flux install --export > $out";
      };

      cilium-crds = pkgs.stdenv.mkDerivation {
        name = "cilium-crds";
        src = pkgs.fetchgit {
          url = "https://github.com/cilium/cilium.git";
          rev = "v1.15.0-rc.0";
          nonConeMode = true;
          sparseCheckout = [ "pkg/k8s/apis/cilium.io/client/crds" ];
          hash = "sha256-+iu/hM/5DPJydYoVIGaTsZ2omPwpmiKUD+ToLNhBU5w=";
        };
        nativeBuildInputs = [ pkgs.yq-go ];
        installPhase = ''
          readarray -t files <<< "$(find . -type f -name "*.yaml")"
          mkdir -p cue.mod/gen
          yq . "''${files[@]}" > "$out"
        '';
      };

      gateway-crds = pkgs.fetchurl {
        url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/experimental-install.yaml";
        hash = "sha256-bGAdzteHKpQNdvpmeuEmunGMtMbblw0Lq0kSjswRkqM=";
      };

      charts = cue.charts {
        cilium.src = pkgs.fetchurl {
          # renovate: helmRepo=helm.cilium.io chart=cilium version=1.14.5
          url = "https://helm.cilium.io/cilium-1.15.0-rc.0.tgz";
          hash = "sha256-TKVEoMtL4rx2ndVW+0d/wep4vW7wRuOkkIPg6cMN6WM=";
        };
        external-secrets.crdValues."installCRDs" = true;
        external-secrets.src = pkgs.fetchurl {
          # renovate: helmRepo=charts.external-secrets.io chart=external-secrets version=0.9.10
          url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.9.10/external-secrets-0.9.10.tgz";
          hash = "sha256-PQzda4iAX5eAImAmaNd/FebP5wrPNLy9pHEBaMMQcwY=";
        };
        cert-manager.crdValues."installCRDs" = true;
        cert-manager.src = pkgs.fetchurl {
          # renovate: helmRepo=charts.jetstack.io chart=cert-manager version=v1.13.3
          url = "https://charts.jetstack.io/charts/cert-manager-v1.13.3.tgz";
          hash = "sha256-8w8+b3Mn8XHssa1gB531VjmtZGmoDzLltgZnr5UEVdU=";
        };
        rook.crdValues."crds.enable" = true;
        rook.src  = pkgs.fetchurl {
          # renovate: helmRepo=charts.rook.io/release chart=rook-ceph version=v1.13.1
          url = "https://charts.rook.io/release/rook-ceph-v1.13.1.tgz";
          hash = "sha256-76Ttrl2sneMSoe8jXAthanrlR3F5ATxN+Ga9bh1g4vo=";
        };
        gitea.src = pkgs.fetchurl {
          # renovate: helmRepo=dl.gitea.com/charts chart=gitea version=10.0.0
          url = "https://dl.gitea.com/charts/gitea-10.0.0.tgz";
          hash = "sha256-/g93GkdEKhIHqBB8yrrAW6xvtjFIMqI9bhjtOwGoezc=";
        };
        ingress-nginx.src = pkgs.fetchurl {
          url = "https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-4.8.3/ingress-nginx-4.8.3.tgz";
          hash = "sha256-L4iBj1RE+AyBnWAgsGxhXjET1pJUn3ZedOwweeDA7k0=";
        };
      };
    in {
      packages.${system} = rec {
        default = manifests;
        manifests = cue.synth {
          name = "netserv";
          src = ./apps;
          inherit charts;
          extraDefinitions = [ 
            (cue.fromCrds "flux-crds" flux-manifests) 
            (cue.fromCrds "cilium-crds" cilium-crds) 
            (cue.fromCrds "gateway-crds" gateway-crds)
          ];
          extraManifests = {
            flux-components."flux-components.yaml" = flux-manifests;
            cilium."crds.yaml" = gateway-crds;
          };
        };
        ociImages = cue.images {
          name = "oci";
          inherit charts;
          src = default;
        };
      };
      devShells.${system} = {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [ pkgs.cue pkgs.timoni postgresql jq nodejs nodePackages.npm typescript kubernetes-helm flux umoci skopeo weave-gitops yq-go go xxd ];
        };
        push = pkgs.mkShell {
          buildInputs = with pkgs; [ skopeo ];
        };
      };
    };
}
