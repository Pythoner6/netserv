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
      utils = import ./tools/utils.nix {inherit pkgs;};

      flux = pkgs.stdenv.mkDerivation {
        name = "flux";
        src = utils.fetchurlHexDigest {
          url = "https://github.com/fluxcd/flux2/releases/download/v2.2.2/flux_2.2.2_linux_amd64.tar.gz"; 
digest = "292945a94ae370b91fe004e1f41b16063fc87371a61a1fd29958dfd959140a60";
        };
        dontUnpack = true;
        installPhase = "set -e; mkdir -p $out/bin; tar -xzf $src -C $out/bin flux";
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
        cilium.src = utils.fetchurlHexDigest {
          # renovate: helm=https://helm.cilium.io package=cilium version=1.15.0-rc.0
          url = "https://helm.cilium.io/cilium-1.15.0-rc.0.tgz";
          digest = "4ca544a0cb4be2bc769dd556fb477fc1ea78bd6ef046e3a49083e0e9c30de963";
        };
        external-secrets.crdValues."installCRDs" = true;
        external-secrets.src = utils.fetchurlHexDigest {
          # renovate: helm=https://charts.external-secrets.io package=external-secrets version=0.9.10
          url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.9.10/external-secrets-0.9.10.tgz";
          digest = "3d0cdd6b88805f978022602668d77f15e6cfe70acf34bcbda4710168c3107306";
        };
        cert-manager.crdValues."installCRDs" = true;
        cert-manager.src = utils.fetchurlHexDigest {
          # renovate: helm=https://charts.jetstack.io package=cert-manager version=v1.13.3
          url = "https://charts.jetstack.io/charts/cert-manager-v1.13.3.tgz";
          digest = "f30f3e6f7327f171ecb1ad60079df55639ad6469a80f32e5b60667af950455d5";
        };
        rook.crdValues."crds.enable" = true;
        rook.src  = utils.fetchurlHexDigest {
          # renovate: helm=https://charts.rook.io/release package=rook-ceph version=v1.13.1
          url = "https://charts.rook.io/release/rook-ceph-v1.13.1.tgz";
          digest = "efa4edae5dac9de312a1ef235c0b616a7ae5477179013c4df866bd6e1d60e2fa";
        };
        gitea.src = utils.fetchurlHexDigest {
          # renovate: helm=https://dl.gitea.com/charts package=gitea version=10.0.0
          url = "https://dl.gitea.com/charts/gitea-10.0.0.tgz";
          digest = "fe0f771a47442a1207a8107ccabac05bac6fb6314832a23d6e18ed3b01a87b37";
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
