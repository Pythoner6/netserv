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

      charts = cue.charts {
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
          # renovate: helmRepo=charts.rook.io/release chart=rook-ceph version=v1.13.0
          url = "https://charts.rook.io/release/rook-ceph-v1.13.0.tgz";
          hash = "sha256-MgB79G9D8TArYezjqYFHcpNYU7vXTTL5kdREOWaiub8=";
        };
        gitea.src = pkgs.fetchurl {
          # renovate: helmRepo=dl.gitea.com/charts chart=gitea version=9.6.1
          url = "https://dl.gitea.com/charts/gitea-9.6.1.tgz";
          hash = "sha256-gl+Vs6oQgZDg4TjMIy1aSkNLaIUvgXxfSzYYfiwJtlY=";
        };
        ingress-nginx.src = pkgs.fetchurl {
          url = "https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-4.8.4/ingress-nginx-4.8.4.tgz";
          hash = "sha256-GBF0oU2cwCJ0eyyY8OgG2SGwBEFwTacqWoXegWyKCPs=";
        };
      };
    in {
      packages.${system} = rec {
        default = manifests;
        manifests = cue.synth {
          name = "netserv";
          src = ./apps;
          inherit charts;
          extraDefinitions = [ (cue.fromCrds "flux-crds" flux-manifests) ];
          extraManifests = {
            flux-components."flux-components.yaml" = flux-manifests;
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
          buildInputs = with pkgs; [ pkgs.cue pkgs.timoni postgresql jq nodejs nodePackages.npm typescript kubernetes-helm fluxcd umoci skopeo weave-gitops yq-go go xxd ];
        };
        push = pkgs.mkShell {
          buildInputs = with pkgs; [ skopeo ];
        };
      };
    };
}
