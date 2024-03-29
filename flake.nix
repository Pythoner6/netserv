{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs@{ self, nixpkgs, flake-parts, rust-overlay, crane }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];
      perSystem = { pkgs, system, ... }: let 
        name = "netserv";
        src = ./.;
        lib = pkgs.lib;

        kubeVersion = "v1.29.0";

        cue = import ./tools/cue.nix {inherit pkgs kubeVersion;};
        oci = import ./tools/oci.nix {inherit pkgs;};
        utils = import ./tools/utils.nix {inherit pkgs;};
        gerrit = import ./tools/gerrit.nix {inherit pkgs;};

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

        tekton-operator-manifest = utils.fetchurlHexDigest {
          # renovate: github-release-attachments package=tektoncd/operator version=v0.70.0
          url = "https://github.com/tektoncd/operator/releases/download/v0.70.0/release.yaml";
          digest = "ee7d9c1681048d265cd83d08225e68963450d061bf4331a936d5b52ceb2ce6d0";
        };

        charts = cue.charts {
          cilium.src = utils.fetchurlHexDigest {
            # renovate: helm=https://helm.cilium.io package=cilium version=1.15.1
            url = "https://helm.cilium.io/cilium-1.15.1.tgz";
            digest = "f5e9ba3b7a98fb1d391ff98b3af0bb711f61aa2d585b24554c1b2946fe5d5ea1";
          };
          external-secrets.crdValues."installCRDs" = true;
          external-secrets.src = utils.fetchurlHexDigest {
            # renovate: helm=https://charts.external-secrets.io package=external-secrets version=0.9.13
            url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.9.13/external-secrets-0.9.13.tgz";
            digest = "30bd50c71d818e70f05893a7605c13d66f934b948d337ef92dc91eaed7d29bdb";
          };
          cert-manager.crdValues."installCRDs" = true;
          cert-manager.src = utils.fetchurlHexDigest {
            # renovate: helm=https://charts.jetstack.io package=cert-manager version=v1.14.4
            url = "https://charts.jetstack.io/charts/cert-manager-v1.14.4.tgz";
            digest = "5775fdbc1881d6e510df76d38753af54b86bd14caa8edb28fdbb79527042dede";
          };
          cert-manager-csi-driver.src = utils.fetchurlHexDigest {
            # renovate: helm=https://charts.jetstack.io package=cert-manager-csi-driver version=v0.7.1
            url = "https://charts.jetstack.io/charts/cert-manager-csi-driver-v0.7.1.tgz";
            digest = "0a74ad7fd439f1f3e6801ff270f1e0776b2afa62be889f34aa752b600a8f4bea";
          };
          rook.crdValues."crds.enable" = true;
          rook.src  = utils.fetchurlHexDigest {
            # renovate: helm=https://charts.rook.io/release package=rook-ceph version=v1.13.6
            url = "https://charts.rook.io/release/rook-ceph-v1.13.6.tgz";
            digest = "d7a65492579eaf27cfd5e27ab05871c6f339ab30915444c1dd01782b712ce86a";
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
            # renovate: helm=https://charts.gitlab.io package=gitlab version=7.9.2
            url = "https://gitlab-charts.s3.amazonaws.com/gitlab-7.9.2.tgz";
            digest = "24807c8019062642854da1468c7855ba922c22af8856cebcab18814d06cd0f97";
          };
          scylla-operator.src = utils.fetchurlHexDigest {
            # renovate: helm=https://storage.googleapis.com/scylla-operator-charts/stable package=scylla version=v1.11.3
            url = "https://scylla-operator-charts.storage.googleapis.com/stable/scylla-operator-vv1.11.3.tgz";
            digest = "ce2019236cdd6370968f51807bbe2aa5ebf25ebf94e8b0a0c903f52be07533eb";
          };
          strimzi-kafka-operator.src = utils.fetchurlHexDigest {
            # renovate: github-release-attachments package=strimzi/strimzi-kafka-operator version=0.40.0
            url = "https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.40.0/strimzi-kafka-operator-helm-3-chart-0.40.0.tgz";
            digest = "a005735c8b397f92ef6c599023a7ee1f2354eabbd8f0282b192f331f02592cc1";
          };
        };
        alternator-credentials = let 
            craneLib = (crane.mkLib pkgs).overrideToolchain pkgs.rust-bin.stable.latest.default;
        in craneLib.buildPackage {
          src = craneLib.cleanCargoSource (craneLib.path ./src/alternator-credentials);
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [ pkgs.openssl.dev ];
          strictDeps = true;
        };
        gerrit-image = oci.fromDockerArchive {
          name = "gerrit-image-oci";
          src = gerrit.gerrit-image alternator-credentials;
        };
      in {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [rust-overlay.overlays.default];
          config = {};
        };
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
              tekton."operator"."manifest.yaml" = tekton-operator-manifest;
            };
            images = {
              attic-token-service = attic-token-service-image;
              gerrit = gerrit-image;
            };
          };
          ociImages = cue.images {
            name = "oci";
            inherit charts;
            images = {
              attic-token-service = attic-token-service-image;
              gerrit = gerrit-image;
            };
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
          #attic-token-service = pkgs.rustPlatform.buildRustPackage {
          #  name = "attic-token-service";
          #  src = ./src/attic-token-service;
          #  #cargo = pkgs.rust-bin.stable.latest.default.override {
          #  cargo = pkgs.pkgsStatic.rust-bin.fromRustupToolchain {
          #    channel = "stable";
          #    targets = [ "x86_64-unknown-linux-musl" ];
          #  };
          #  cargoLock = {
          #    lockFile = ./src/attic-token-service/Cargo.lock;
          #    outputHashes = {
          #      "attic-0.1.0" = "sha256-+ACjzPhs0ejAmKMiAM/QGooRt5oUBBm3HQTD59R9rS4=";                
          #      "nix-base32-0.1.2-alpha.0" = "sha256-wtPWGOamy3+ViEzCxMSwBcoR4HMMD0t8eyLwXfCDFdo=";
          #    };
          #  };
          #};
          attic-token-service = let 
            target = (builtins.head (pkgs.lib.strings.splitString "-" system)) + "-unknown-linux-musl";
            craneLib = (crane.mkLib pkgs).overrideToolchain (pkgs.rust-bin.stable.latest.default.override {
              targets = [ target ];
            });
          in craneLib.buildPackage {
            src = craneLib.cleanCargoSource (craneLib.path ./src/attic-token-service);
            strictDeps = true;
            cargoExtraArgs = "--target ${target}";
          };
          attic-token-service-image = oci.fromDockerArchive {
            name = "attic-token-service-image-oci";
            src = pkgs.dockerTools.buildLayeredImage {
              name = "attic-token-service-image";
              contents = [ attic-token-service ];
              config.Cmd = [ "attic-token-service" ];
            };
          };
          pkl-src = pkgs.fetchFromGitHub {
            owner = "apple";
            repo = "pkl";
            rev = "0.25.2";
            hash = "sha256-nYFK1GPghtm9RAEhbSqeduYGTCEtWRHnKMLoECRxBak=";
          };
          pkl = pkgs.stdenv.mkDerivation (let 
            deps = pkgs.stdenv.mkDerivation {
              name = "pkl-deps";
              src = pkl-src;
              nativeBuildInputs = [pkgs.gradle_7 pkgs.git];
              buildPhase = ''
                cd pkl-cli
                gradle tasks --all
                gradle --no-daemon installDist
                ls ~/.gradle/caches/modules-2/files-2.1
              '';
              installPhase = ''
                gradle --no-daemon -Dmaven.repo.local=$out/.m2 cacheToMavenLocal
              '';
              outputHashAlgo = "sha256";
              outputHashMode = "recursive";
              outputHash = "";
            };
          in {
            name = "pkl";
            src = pkl-src;
            nativeBuildInputs = [ pkgs.gradle pkgs.makeWrapper deps pkgs.rsync ];
            buildPhase = ''
              touch $out
            '';
          });
        };
        devShells = {
          default = pkgs.mkShell {
          #default = ((crane.mkLib pkgs).overrideToolchain (pkgs.rust-bin.stable.latest.default.override {extensions = ["rust-analyzer"];})).devShell {
            buildInputs = with pkgs; [ pkgs.cue pkgs.timoni postgresql jq nodejs nodePackages.npm typescript kubernetes-helm flux umoci skopeo weave-gitops yq-go go xxd talosctl pkgs.crane openldap operator-sdk jdk19 maven gradle pkgs.cargo pkgs.rustc gcc pkg-config openssl.dev cassandra ];
          };
          push = pkgs.mkShell {
            buildInputs = [ pkgs.crane ];
          };
        };
      };
    };
}
