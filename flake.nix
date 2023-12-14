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

      kube-version = "v1.27.3";

      flux = "${pkgs.fetchzip {
        url = "https://github.com/fluxcd/flux2/releases/download/v2.2.0/flux_2.2.0_linux_amd64.tar.gz";
        hash = "sha256-Qw6x2ljZtvOBXe2KiGbeEN1APDeGbWGT3/kE5JIMWNs=";
      }}/flux";
      metallb-chart = pkgs.fetchzip {
        url = "https://github.com/metallb/metallb/releases/download/metallb-chart-0.13.12/metallb-0.13.12.tgz";
        hash = "sha256-W+GcNyNLEH5fV00436PO8RTXDdWn1BttE/Y3JbaN41A=";
      };
      cert-manager-chart = pkgs.fetchzip {
        url = "https://charts.jetstack.io/charts/cert-manager-v1.13.1.tgz";
        hash = "sha256-wAHlpNAc0bXW4vL7ctK80RhkgY4iLCUIKFSqNPSTfRQ=";
      };
      cert-manager-chart-zip = pkgs.fetchurl {
        url = "https://charts.jetstack.io/charts/cert-manager-v1.13.3.tgz";
        hash = "sha256-8w8+b3Mn8XHssa1gB531VjmtZGmoDzLltgZnr5UEVdU=";
      };
      traefik-chart = pkgs.fetchzip {
        url = "https://traefik.github.io/charts/traefik/traefik-25.0.0.tgz";
        hash = "sha256-ua8KnUB6MxY7APqrrzaKKSOLwSjDYkk9tfVkb1bqkVM=";
      };
      rook-chart = pkgs.fetchzip {
        url = "https://charts.rook.io/release/rook-ceph-v1.12.7.tgz";
        hash = "sha256-Z/Y0EdN2Qu56HnO5uN8SOZA0rMTC91eqmn7NMwX+M4Q=";
      };
      rook-chart-zip = pkgs.fetchurl {
        url = "https://charts.rook.io/release/rook-ceph-v1.12.9.tgz";
        hash = "sha256-sA9rMy64a5WomstxCISojeXcmQuI56ZDrYCMRQ3cn1Y=";
      };
      external-secrets-chart = pkgs.fetchzip {
        url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.9.7/external-secrets-0.9.7.tgz";
        hash = "sha256-uAprYgJ+iVSH+D0dR0nyUbna4hMi/Cpl9xHd/JNGkqM=";
      };
      external-secrets-chart-zip = pkgs.fetchurl {
        url = "https://github.com/external-secrets/external-secrets/releases/download/helm-chart-0.9.9/external-secrets-0.9.9.tgz";
        hash = "sha256-IH23aIHpWns5hOEsEsV/P4PGgr1zzkxjd/5960tLEMI=";
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
      gitea-chart-zip = pkgs.fetchurl {
        url = "https://dl.gitea.com/charts/gitea-9.6.1.tgz";
        hash = "sha256-gl+Vs6oQgZDg4TjMIy1aSkNLaIUvgXxfSzYYfiwJtlY=";
      };
      ingress-nginx-chart-zip = pkgs.fetchurl {
        url = "https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-4.8.4/ingress-nginx-4.8.4.tgz";
        hash = "";
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
      vendorCRDs = {name, src}: pkgs.stdenv.mkDerivation {
        inherit name;
        unpackPhase = "true";
        buildInputs = with pkgs; [ kubernetes-helm timoni yq-go ];
        installPhase = ''
          mkdir $out
          mkdir cue.mod
          timoni mod vendor crd -f ${src}
          cp -a cue.mod/gen/. $out
        '';
      };
      vendorChartCRDs = {name, chart, key ? ""}: pkgs.stdenv.mkDerivation {
        inherit name;
        unpackPhase = "true";
        buildInputs = with pkgs; [ kubernetes-helm timoni yq-go ];
        installPhase = ''
          mkdir $out
          mkdir cue.mod
          if [[ ! -z "${key}" ]]; then
            enableCRD="--set ${key}=true"
          fi
          helm template "${chart}" --include-crds --kube-version ${kube-version} $enableCRD | tee rendered.yaml >/dev/null
          yq -i 'select(.kind == "CustomResourceDefinition")' rendered.yaml
          if [[ "${chart}" == "${rook-chart-zip}" ]]; then
            yq -i 'with(select(.metadata.name == "objectbuckets.objectbucket.io").spec.versions[].schema.openAPIV3Schema.properties.spec.properties.authentication; del(.))' rendered.yaml
          fi
          timoni mod vendor crd -f rendered.yaml
          cp -a cue.mod/gen/. $out
        '';
      };
      buildImage = {name, src}: pkgs.stdenv.mkDerivation {
        inherit name;
        inherit src;
        nativeBuildInputs = with pkgs; [ umoci ];
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
        deps = pkgs.buildNpmPackage rec {
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
        default = pkgs.buildNpmPackage rec {
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
            ln -s ${deps} deps.tgz
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
            cp -a flux-system $out/apps
            umoci init --layout $out/oci-image
            umoci new --image $out/oci-image:latest
            umoci unpack --uid-map 0:$(id -u) --gid-map 0:$(id -g) --image $out/oci-image:latest bundle
            cp -a $out/apps/flux-system bundle/rootfs
            #cp -a $out/apps/weaveworks-gitops bundle/rootfs
            umoci repack --image $out/oci-image:latest bundle
          '';
        };
        flux-manifests = pkgs.stdenv.mkDerivation {
          name = "flux-manifests";
          unpackPhase = "true";
          installPhase = ''
            ${flux} install --export > $out
          '';
        };
        flux-crds = vendorCRDs {
          name = "flux-crds";
          src = flux-manifests;
        };
        cert-manager-crds = vendorChartCRDs {
          name = "cert-manager-crds";
          chart = cert-manager-chart-zip;
          key = "installCRDs";
        };
        rook-crds = vendorChartCRDs {
          name = "rook-crds";
          chart = rook-chart-zip;
          key = "crds.enabled";
        };
        external-secrets-crds = vendorChartCRDs {
          name = "external-secrets-crds";
          chart = external-secrets-chart-zip;
          key = "installCRDs";
        };
        vendor-k8s = pkgs.buildGoModule {
          name = "vendor-k8s";
          src = ./cue-k8s-go;
          nativeBuildInputs = with pkgs; [ cue ];
          vendorHash = "sha256-IHsac33UiHNpr4u82kHGD2SEx4vgrTS/6UogCGZTTes=";
          buildPhase = ''
            cue get go k8s.io/api/...
            cue get go k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1
          '';
          installPhase = ''
            mkdir $out
            cp -a cue.mod/gen/. $out
          '';
        };
        test = pkgs.stdenv.mkDerivation {
          name = "test";
          buildInputs = [vendor-k8s flux-crds cert-manager-crds rook-crds external-secrets-crds];
          nativeBuildInputs = with pkgs; [ cue ];
          src = ./.;
          configurePhase = ''
            mkdir cue.mod/gen/
            IFS=$'\n'; readarray -t gen <<<"$(unset IFS; find $buildInputs -maxdepth 1 -mindepth 1 -type d)"
            ln -s "${"$"}{gen[@]}" cue.mod/gen/
          '';
          buildPhase = "true";
          installPhase = ''
            IFS=$'\n'; readarray -t apps <<<"$(find ./apps/ -maxdepth 1 -mindepth 1 -type d -printf '%f\n')"
            for app in "${"$"}{apps[@]}"; do
              mkdir -p $out/$app/
              if [[ "$app" == "flux-system" ]]; then
                cp ${flux-manifests} $out/$app/flux.yaml
              fi
              cue export ./apps/$app:resources -e resources --out text > $out/$app/resources.yaml
              cue export ./apps/$app:kustomization -e kustomization --out text > $out/$app/kustomization.yaml
            done
          '';
        };
        test-img = buildImage {
          name = "test-img";
          src = test;
        };
      };
      devShells.${system} = {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [ cue timoni postgresql jq nodejs nodePackages.npm typescript kubernetes-helm fluxcd umoci skopeo weave-gitops yq-go go xxd ];
        };
        push = pkgs.mkShell {
          buildInputs = with pkgs; [ skopeo ];
        };
      };
    };
}
