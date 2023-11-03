{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs, nixpkgs-unstable }:
    let
      system = "x86_64-linux";
      name = "netserv";
      src = ./.;
      pkgs = nixpkgs.legacyPackages.${system};
      pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};

      metallb-chart = pkgs.fetchzip {
        url = "https://github.com/metallb/metallb/releases/download/metallb-chart-0.13.12/metallb-0.13.12.tgz";
        hash = "sha256-W+GcNyNLEH5fV00436PO8RTXDdWn1BttE/Y3JbaN41A=";
      };
      cert-manager-chart = pkgs.fetchzip {
        url = "https://charts.jetstack.io/charts/cert-manager-v1.13.1.tgz";
        hash = "sha256-wAHlpNAc0bXW4vL7ctK80RhkgY4iLCUIKFSqNPSTfRQ=";
      };
      traefik-chart = pkgs.fetchzip {
        url = "https://traefik.github.io/charts/traefik/traefik-25.0.0.tgz";
        hash = "sha256-ua8KnUB6MxY7APqrrzaKKSOLwSjDYkk9tfVkb1bqkVM=";
      };
      rook-chart = pkgs.fetchzip {
        url = "https://charts.rook.io/release/rook-ceph-v1.12.7.tgz";
        hash = "sha256-Z/Y0EdN2Qu56HnO5uN8SOZA0rMTC91eqmn7NMwX+M4Q=";
      };
      external-secrets-chart = pkgs.fetchzip {
        url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.9.7/external-secrets-0.9.7.tgz";
        hash = "sha256-uAprYgJ+iVSH+D0dR0nyUbna4hMi/Cpl9xHd/JNGkqM=";
      };
      local-path-provisioner-chart = pkgs.stdenv.mkDerivation {
        name = "local-path-provisioner-chart";
        src = pkgs.fetchgit {
          url = "https://github.com/rancher/local-path-provisioner.git";
          rev = "v0.0.24";
          nonConeMode = true;
          sparseCheckout = [ "deploy/chart/local-path-provisioner" ];
          hash = "sha256-AOcr3rVsjkvKY6SZjf0zZncX2Lh6dX3nfCF6UJ3Ayws=";
        };
        buildPhase = "true";
        installPhase = ''
          cp -r deploy/chart/local-path-provisioner/ $out/
        '';
      };
      weaveworks-gitops-chart = pkgs.stdenv.mkDerivation {
        name = "weaveworks-gitops-chart";
        src = pkgs.fetchgit {
          url = "https://github.com/weaveworks/weave-gitops.git";
          rev = "v0.35.0";
          nonConeMode = true;
          sparseCheckout = [ "charts/gitops-server" ];
          hash = "sha256-uvooIZVUm9+ykxMZg8NoQxFXXLbDFFFgILz/fU5X/ug=";
        };
        buildPhase = "true";
        installPhase = ''
          cp -r charts/gitops-server/ $out/
        '';
      };
      cockroachdb-manifest = pkgs.stdenv.mkDerivation {
        name = "cockroachdb";
        src = pkgs.fetchgit {
          url = "https://github.com/cockroachdb/cockroach-operator.git";
          rev = "v2.12.0";
          nonConeMode = true;
          sparseCheckout = [ "install" ];
          hash = "sha256-UCgy6LknYQp4XFHftc0lKfdVGVIWy0ioccAeFJAMc9k=";
        };
        patches = [ ./patches/crdb-enable-affinity.patch ];
        buildPhase = "true";
        installPhase = ''
          cp -r install/. $out/
        '';
      };
      gitea-chart = pkgs.fetchzip {
        url = "https://dl.gitea.com/charts/gitea-9.5.1.tgz";
        hash = "sha256-UYslC1WgnMP/Qk3wCVU/lBGl/QyBsBX+8zU40eyJUOo=";
      };
      #patch-gitea = pkgs.gitea.overrideAttrs (old: rec {
      #  patches = old.patches ++ [ ./patches/gitea-cockroach.patch ];
      #  version = "1.20.5";
      #  src = pkgs.fetchurl {
      #    url = "https://dl.gitea.com/gitea/${version}/gitea-src-${version}.tar.gz";
      #    hash = "sha256-cH/AHsFXOdvfSfj9AZUd3l/RlYE06o1ByZu0vvGQuXw=";
      #  };
      #  buildPhase = old.buildPhase + ''
      #    go build contrib/environment-to-ini/environment-to-ini.go
      #  '';
      #  postInstall = old.postInstall + ''
      #    cp ./environment-to-ini $out/bin/environment-to-ini
      #  '';
      #});
    in rec {
      packages.x86_64-linux.deps = pkgs.buildNpmPackage rec {
        name = "netserv-deps";
        pname = "netserv-deps";
        src = ./deps;
        npmDepsHash = "sha256-HSBAyeJNT6HFvRtsEGFyWX+hDmgbJ2+4k9J9CXe9bAw=";
        nativeBuildInputs = with pkgs; [ yq-go kubernetes-helm nodejs nodePackages.npm typescript ];
        makeCacheWritable = true;
        npmBuildFlags = [
          "--metallb=${metallb-chart}" 
          "--traefik=${traefik-chart}" 
          "--rook=${rook-chart}" 
          "--external-secrets=${external-secrets-chart}" 
          "--local-path-provisioner=${local-path-provisioner-chart}" 
          "--cockroachdb=${cockroachdb-manifest}"
          "--certmanager=${cert-manager-chart}"
        ];
        postBuild = ''
          npm pack
        '';
        installPhase = ''
          cp pythoner6-netserv-deps-0.0.0.tgz $out
        '';
      };
      packages.x86_64-linux.default = pkgs.buildNpmPackage rec {
        name = "netserv-main";
        pname = "netserv-main";
        src = ./main;
        npmDepsHash = "sha256-sWj3KBuxqq1StZ4XuQscpe3zy33YT8VLFKasq1zWyOU=";
        nativeBuildInputs = with pkgs; [ yq-go kubernetes-helm nodejs nodePackages.npm typescript umoci ];
        makeCacheWritable = true;
        npmBuildFlags = [
          "--gitea=${gitea-chart}"
          "--gitops=${weaveworks-gitops-chart}"
        ];
        preBuild = ''
          ln -s ${packages.x86_64-linux.deps} deps.tgz
          npm i deps.tgz
        '';
        installPhase = ''
          mkdir -p $out/apps
          for dir in dist node_modules/@pythoner6/netserv-deps/dist; do
            IFS=$'\n'
            for chart in $(find $dir -type f); do
              n="$(basename --suffix=.k8s.yaml "$chart")"
              mkdir -p "$out/apps/$n/manifests"
              cp "$chart" "$out/apps/$n/manifests/$n.yaml"
              cp kustomization.yaml "$out/apps/$n/"
              cat flux.yaml | sed "s/{{NAME}}/$n/" > "$out/apps/$n/flux.yaml"
            done
          done
          set -x
          cp -a flux-system $out/apps
          umoci init --layout $out/oci-image
          umoci new --image $out/oci-image:latest
          umoci unpack --uid-map 0:$(id -u) --gid-map 0:$(id -g) --image $out/oci-image:latest bundle
          cp -a $out/apps/flux-system bundle/rootfs
          cp -a $out/apps/weaveworks-gitops bundle/rootfs
          umoci repack --image $out/oci-image:latest bundle
        '';
      };
      devShells.x86_64-linux.default = pkgs.mkShell {
        buildInputs = with pkgs; [ postgresql jq nodejs nodePackages.npm typescript kubernetes-helm pkgs-unstable.fluxcd umoci skopeo pkgs-unstable.weave-gitops go ];
      };
      devShells.x86_64-linux.push = pkgs.mkShell {
        buildInputs = with pkgs; [ skopeo ];
      };
    };
}
