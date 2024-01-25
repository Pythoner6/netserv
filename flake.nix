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

      versions = builtins.fromJSON (builtins.readFile ./versions.json);
      stripv = v: builtins.head (builtins.match "^v?(.*)" v);

      flux = pkgs.stdenv.mkDerivation {
        pname = versions.flux.package;
        version = versions.flux.version;
        src = utils.fetchurlHexDigest {
          url = "https://github.com/${versions.flux.package}/releases/download/${versions.flux.version}/flux_${stripv versions.flux.version}_linux_amd64.tar.gz"; 
          digest = versions.flux.digest;
        };
        dontUnpack = true;
        installPhase = "set -e; mkdir -p $out/bin; tar -xzf $src -C $out/bin flux";
      };

      talosctl = pkgs.stdenv.mkDerivation {
        pname = "talosctl";
        version = versions.talos.version;
        src = utils.fetchurlHexDigest {
          url = "https://github.com/${versions.talos.package}/releases/download/${versions.talos.version}/talosctl-linux-amd64";
          digest = versions.talos.talosctlDigest;
        };
        dontUnpack = true;
        installPhase = "set -e; mkdir -p $out/bin; cp $src $out/bin/talosctl; chmod +x $out/bin/talosctl";
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
          # renovate: helm=https://charts.external-secrets.io package=external-secrets version=0.9.11
          url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.9.11/external-secrets-0.9.11.tgz";
          digest = "fec0e3c284d779963f4c0df7274cf0a81b428967b1f9c5063a2d5af4241a021f";
        };
        cert-manager.crdValues."installCRDs" = true;
        cert-manager.src = utils.fetchurlHexDigest {
          # renovate: helm=https://charts.jetstack.io package=cert-manager version=v1.13.3
          url = "https://charts.jetstack.io/charts/cert-manager-v1.13.3.tgz";
          digest = "f30f3e6f7327f171ecb1ad60079df55639ad6469a80f32e5b60667af950455d5";
        };
        cert-manager-csi-driver.src = utils.fetchurlHexDigest {
          # renovate: helm=https://charts.jetstack.io package=cert-manager-csi-driver version=v0.6.0
          url = "https://charts.jetstack.io/charts/cert-manager-csi-driver-v0.6.0.tgz";
          digest = "10e938d3cc27919970d19871c1f2da2e591a6a85630979e2166600c88d3f4946";
        };
        rook.crdValues."crds.enable" = true;
        rook.src  = utils.fetchurlHexDigest {
          # renovate: helm=https://charts.rook.io/release package=rook-ceph version=v1.13.1
          url = "https://charts.rook.io/release/rook-ceph-v1.13.1.tgz";
          digest = "efa4edae5dac9de312a1ef235c0b616a7ae5477179013c4df866bd6e1d60e2fa";
        };
        gitea.src = utils.fetchurlHexDigest {
          # renovate: helm=https://dl.gitea.com/charts package=gitea version=10.0.2
          url = "https://dl.gitea.com/charts/gitea-10.0.2.tgz";
          digest = "0b52d987e0e3a214209d56c5f49b696f7a858aac042ca32d9c28858a762bd41d";
        };
        democratic-csi.src = utils.fetchurlHexDigest {
          # renovate: helm=https://democratic-csi.github.io/charts package=democratic-csi version=0.14.5
          url = "https://github.com/democratic-csi/charts/releases/download/democratic-csi-0.14.5/democratic-csi-0.14.5.tgz";
          digest = "3c6a7356beb1e473de9fdfec0ff8e583be3e254fc1b5f7468a5349e3c30083f1";
        };
        cloudnative-pg.src = utils.fetchurlHexDigest {
          # renovate: helm=https://cloudnative-pg.github.io/charts package=cloudnative-pg version=0.20.0
          url = "https://cloudnative-pg.github.io/charts/cloudnative-pg-0.20.0.tgz";
          digest = "44d55c35d46a08b79c4b158005363ae9b4f07640afede9133c4776000893f786";
        };
        gitlab.src = utils.fetchurlHexDigest {
          # renovate: helm=https://charts.gitlab.io package=gitlab version=7.8.1
          url = "https://gitlab-charts.s3.amazonaws.com/gitlab-7.8.1.tgz";
          digest = "cd7915bb9b0b00059ee1f900a4801608c551fd1797986e2842bad263790ff1bb";
        };
      };
    in {
      packages.${system} = rec {
        default = manifests;
        manifests = cue.synth {
          name = "netserv";
          #src = lib.sources.sourceFilesBySuffices ./. [".cue"];
          src = ./.;
          appsSubdir = "k8s";
          rootAppName = "root";
          inherit charts;
          extraDefinitions = [ 
            (cue.fromCrds "flux-crds" flux-manifests) 
            (cue.fromCrds "cilium-crds" cilium-crds) 
            (cue.fromCrds "gateway-crds" gateway-crds)
          ];
          extraManifests = {
            flux-components.components."flux-components.yaml" = flux-manifests;
            cilium.gateway-crds."crds.yaml" = gateway-crds;
          };
        };
        ociImages = cue.images {
          name = "oci";
          inherit charts;
          src = default;
        };
        openldap = pkgs.dockerTools.buildLayeredImage {
          name = "openldap";
          #config.Cmd = let openldap = pkgs.openldap.overrideAttrs (final: prev: {configureFlags = prev.configureFlags ++ ["--enable-syncprov"];}); in ["${openldap}/libexec/slapd" "-d" "-1" "-F" "/config" "-h" "ldap://0.0.0.0/"];
          #config.Cmd = ["${pkgs.openldap}/libexec/slapd" "-d" "-1" "-F" "/config" "-h" "ldap://0.0.0.0/"];
          #config.Entrypoint = ["${pkgs.bash}/bin/bash" "-c" "\"${pkgs.openldap}/libexec/slapd -d -1 -F /config -h ldap://$1/\""];
          config.Entrypoint = [(pkgs.stdenv.mkDerivation {
            name = "entrypoint.sh";
            dontUnpack = true;
            installPhase = ''
              cat <<'EOF' > "$out"
              #!${pkgs.bash}/bin/bash
              echo "$@"
              set -x
              exec ${pkgs.openldap}/libexec/slapd -d -1 -F /config -h "$1"
              EOF
              chmod +x $out
            '';
          })];
        };
      };
      devShells.${system} = {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [ pkgs.cue pkgs.timoni postgresql jq nodejs nodePackages.npm typescript kubernetes-helm flux umoci skopeo weave-gitops yq-go go xxd talosctl crane ];
        };
        push = pkgs.mkShell {
          buildInputs = with pkgs; [ crane ];
        };
      };
    };
}
