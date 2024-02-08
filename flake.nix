{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };
  outputs = inputs@{ self, nixpkgs, flake-parts }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];
      perSystem = { pkgs, system, ... }: let 
        name = "netserv";
        src = ./.;
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
          installPhase = ''
            set -e; mkdir -p $out/bin; tar -xzf $src -C $out/bin flux
          '';
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
            # renovate: helm=https://helm.cilium.io package=cilium version=1.15.0
            url = "https://helm.cilium.io/cilium-1.15.0.tgz";
            digest = "ef44c23339e62df7994eab0da956f999b67289d9f36efcb26cefd55891975daa";
          };
          external-secrets.crdValues."installCRDs" = true;
          external-secrets.src = utils.fetchurlHexDigest {
            # renovate: helm=https://charts.external-secrets.io package=external-secrets version=0.9.11
            url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.9.11/external-secrets-0.9.11.tgz";
            digest = "fec0e3c284d779963f4c0df7274cf0a81b428967b1f9c5063a2d5af4241a021f";
          };
          cert-manager.crdValues."installCRDs" = true;
          cert-manager.src = utils.fetchurlHexDigest {
            # renovate: helm=https://charts.jetstack.io package=cert-manager version=v1.14.2
            url = "https://charts.jetstack.io/charts/cert-manager-v1.14.2.tgz";
            digest = "45c13a8a3b0cceea09301bb6f847a8b0ffdc975ed56975e895ac85c651bcde5c";
          };
          cert-manager-csi-driver.src = utils.fetchurlHexDigest {
            # renovate: helm=https://charts.jetstack.io package=cert-manager-csi-driver version=v0.7.1
            url = "https://charts.jetstack.io/charts/cert-manager-csi-driver-v0.7.1.tgz";
            digest = "0a74ad7fd439f1f3e6801ff270f1e0776b2afa62be889f34aa752b600a8f4bea";
          };
          rook.crdValues."crds.enable" = true;
          rook.src  = utils.fetchurlHexDigest {
            # renovate: helm=https://charts.rook.io/release package=rook-ceph version=v1.13.3
            url = "https://charts.rook.io/release/rook-ceph-v1.13.3.tgz";
            digest = "e73b48b91ab9b5f80bb2961fea4203057c84a26945aadcf75bf0d0075d3babdb";
          };
          democratic-csi.src = utils.fetchurlHexDigest {
            # renovate: helm=https://democratic-csi.github.io/charts package=democratic-csi version=0.14.5
            url = "https://github.com/democratic-csi/charts/releases/download/democratic-csi-0.14.5/democratic-csi-0.14.5.tgz";
            digest = "3c6a7356beb1e473de9fdfec0ff8e583be3e254fc1b5f7468a5349e3c30083f1";
          };
          cloudnative-pg.src = utils.fetchurlHexDigest {
            # renovate: helm=https://cloudnative-pg.github.io/charts package=cloudnative-pg version=0.20.1
            url = "https://cloudnative-pg.github.io/charts/cloudnative-pg-0.20.1.tgz";
            digest = "c9fd95e3a56241d99f6a27f801488e6d70dfdd9bcd0e49420f28847d9377414d";
          };
          gitlab.src = utils.fetchurlHexDigest {
            # renovate: helm=https://charts.gitlab.io package=gitlab version=7.8.2
            url = "https://gitlab-charts.s3.amazonaws.com/gitlab-7.8.2.tgz";
            digest = "a17344e044350fd37da4a2acdaf61eea7b6e77ee214a955424b8d164ff251e5e";
          };
        };
      in {
        packages = rec {
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
          elector = pkgs.buildGoModule {
            name = "elector";
            src = ./src/elector;
            vendorHash = "sha256-jAU6ZvShaqsrTFz0n8pHU/XlY+R2DOaAYeAytGoPUGg=";
          };
          openldap = pkgs.dockerTools.buildLayeredImage {
            name = "openldap";
            #config.Cmd = let openldap = pkgs.openldap.overrideAttrs (final: prev: {configureFlags = prev.configureFlags ++ ["--enable-syncprov"];}); in ["${openldap}/libexec/slapd" "-d" "-1" "-F" "/config" "-h" "ldap://0.0.0.0/"];
            #config.Cmd = ["${pkgs.openldap}/libexec/slapd" "-d" "-1" "-F" "/config" "-h" "ldap://0.0.0.0/"];
            #config.Entrypoint = ["${pkgs.bash}/bin/bash" "-c" "\"${pkgs.openldap}/libexec/slapd -d -1 -F /config -h ldap://$1/\""];
            #contents = with pkgs; [ bashInteractive coreutils openldap ];
            contents = [ pkgs.openldap pkgs.bash pkgs.coreutils pkgs.curl elector ];
            config.Entrypoint = [(pkgs.stdenv.mkDerivation {
              name = "entrypoint.sh";
              dontUnpack = true;
              installPhase = ''
                cat <<'EOF' > "$out"
                #!/bin/bash
                set -euxo pipefail
                /scripts/ldap_init.sh
                exec /libexec/slapd -d 256 -F /data/config -h "$LISTEN_ADDR"
                EOF
                chmod +x $out
              '';
            })];
          };
          openldap-sidecar = pkgs.dockerTools.buildLayeredImage {
            name = "openldap-sidecar-image";
            contents = [ elector ];
            config.Entrypoint = ["/bin/elector"];
          };
          #ldap-operator = pkgs.maven.buildMavenPackage {
          #  version = "0.0.1";
          #  pname = "ldap-operator";
          #  src = ./src/ldap-operator;
          #  mvnHash = "sha256-CXtpr4oYzQ96oWm+lDe0PBuf1L8OLQ1kS8V1wS2wYSU=";
          #  #mvnParameters = "-P native";
          #  nativeBuildInputs = [pkgs.gcc pkgs.graalvm-ce pkgs.operator-sdk pkgs.makeWrapper];
          #  #installPhase = "mv target $out";
          #  #buildOffline = true;
          #  installPhase = ''
          #    mkdir -p $out/bin $out/share/
          #    cp -a target/quarkus-app $out/share/ldap-operator
          #    makeWrapper ${pkgs.jre}/bin/java $out/bin/ldap-operator --add-flags "-jar $out/share/ldap-operator/quarkus-run.jar"
          #  '';
          #};
          ldap-operator = pkgs.stdenv.mkDerivation (let 
            deps = pkgs.stdenv.mkDerivation {
              name = "ldap-operator-deps";
              src = ./src/ldap-operator;
              nativeBuildInputs = [pkgs.gradle];
              buildPhase = ''
                gradle --no-daemon installDist
              '';
              installPhase = ''
                gradle --no-daemon -Dmaven.repo.local=$out/.m2 cacheToMavenLocal
              '';
              outputHashAlgo = "sha256";
              outputHashMode = "recursive";
              outputHash = "sha256-PfxEWWO0Dfmoa3301htD5sayGTnx32a6n8Dm5NKVpl0=";
            };
          in {
            name = "ldap-operator";
            src = ./src/ldap-operator;
            nativeBuildInputs = [ pkgs.gradle pkgs.makeWrapper deps pkgs.rsync ];
            outputs = ["out" "crds"];
            buildPhase = ''
              gradle --offline --no-daemon -Dmaven.repo.local=${deps}/.m2
              mkdir -p $out/bin $out/share
              mv build/quarkus-app $out/share/ldap-operator
              makeWrapper ${pkgs.jre}/bin/java $out/bin/ldap-operator --add-flags "-jar $out/share/ldap-operator/quarkus-run.jar"
              mkdir $crds
              echo "$crds"
              rsync -r --exclude=kubernetes.json build/kubernetes/ $crds/
            '';
          });
          attic-token-service = pkgs.rustPlatform.buildRustPackage {
            name = "attic-token-service";
            src = ./src/attic-token-service;
            cargoLock = {
              lockFile = ./src/attic-token-service/Cargo.lock;
              outputHashes = {
                "attic-0.1.0" = "sha256-+ACjzPhs0ejAmKMiAM/QGooRt5oUBBm3HQTD59R9rS4=";                
                "nix-base32-0.1.2-alpha.0" = "sha256-wtPWGOamy3+ViEzCxMSwBcoR4HMMD0t8eyLwXfCDFdo=";
              };
            };
          };
          attic-token-service-image = pkgs.dockerTools.buildLayeredImage {
            name = "attic-token-service-image";
            contents = [ attic-token-service ];
            config.Cmd = [ "attic-token-service" ];
          };
        };
        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [ pkgs.cue pkgs.timoni postgresql jq nodejs nodePackages.npm typescript kubernetes-helm flux umoci skopeo weave-gitops yq-go go xxd talosctl crane openldap operator-sdk jdk19 maven gradle pkgs.cargo pkgs.rustc ];
          };
          push = pkgs.mkShell {
            buildInputs = with pkgs; [ crane ];
          };
        };
      };
    };
}
