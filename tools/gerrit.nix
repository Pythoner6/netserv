# License: MIT
{ pkgs }: let
  gerrit-version = "3.9.1";
  gerrit = let
    bazelRunScript = pkgs.writeShellScriptBin "bazel-run" ''
      export HOME="$bazelOut/external/home"
      mkdir -p "$bazelOut/external/home"
      yarn config set cache-folder "$bazelOut/external/yarn_cache"
      exec /bin/bazel "$@"
    '';
    bazel = (pkgs.buildFHSUserEnv {
      name = "bazel";
      targetPkgs = pkgs: [
        (pkgs.bazel.override { enableNixHacks = true; })
        pkgs.jdk17_headless
        pkgs.zlib
        pkgs.python3
        pkgs.curl
        pkgs.nodejs
        pkgs.yarn
        pkgs.git
        bazelRunScript
      ];
      runScript = "/bin/bazel-run";
    }) // { override = x: bazel; };
  in pkgs.lib.makeOverridable pkgs.buildBazelPackage (rec {
    pname = "gerrit";
    version = gerrit-version;
    name = "${pname}-${version}.war";
    src = pkgs.fetchgit {
      url = "https://gerrit.googlesource.com/gerrit";
      rev = "620a819cbf3c64fff7a66798822775ad42c91d8e";
      branchName = "v${version}";
      sha256 = "sha256:1mdxbgnx3mpxand4wq96ic38bb4yh45q271h40jrk7dk23sgmz02";
      fetchSubmodules = true;
    };
    inherit bazel;
    bazelTargets = [ "release" ];
    bazelFlags = [
      "--repository_cache="
      "--disk_cache="
    ];
    removeRulesCC = false;
    fetchConfigured = true;
    fetchAttrs = {
      sha256 = "sha256-C9BrfAMbTTdLHIj5aBnatsvEWDkBHk3xW7soBNYpPHs=";
      preConfigure = ''
        rm .bazelversion
      '';
      preInstall = ''
        # polymer-bridges is a local package (git submodule); yarn for some reason 
        # copies it into the cache with a guid+timestamp which breaks reproducibility
        find "$bazelOut/external/yarn_cache" -type d -name '*polymer-bridges*' -exec rm -rf {} +
        find "$bazelOut/external/yarn_cache" \( -name .yarn-tarball.tgz -or -name .yarn-metadata.json \) -exec chmod 644 {} +
        find . -name node_modules | while read d; do
          mkdir -p "$bazelOut/external/.extra-node-modules-dirs/$(dirname $d)"
          cp -R "$d" "$bazelOut/external/.extra-node-modules-dirs/$d"
        done
      '';
    };
    buildAttrs = {
      preConfigure = ''
        rm .bazelversion
        if [[ -d "$bazelOut/external/.extra-node-modules-dirs/" ]]; then
          cp -R "$bazelOut/external/.extra-node-modules-dirs/." ./
          rm -rf "$bazelOut/external/.extra-node-modules-dirs"
        fi
      '';
      installPhase = ''
        cp bazel-bin/release.war $out
      '';
    };

    passthru = {
      plugins = [
        "codemirror-editor"
        "commit-message-length-validator"
        "delete-project"
        "download-commands"
        "gitiles"
        "hooks"
        "plugin-manager"
        "replication"
        "reviewnotes"
        "singleusergroup"
        "webhooks"
      ];
    };
  });
  buildGerritPlugin = {name, src, depsOutputHash, needsExternalDeps ? false, pluginDeps ? []}: ((gerrit.override {
    name = "${name}.jar";
    src = pkgs.runCommandLocal "${name}-source" {} ''
      cp -R "${gerrit.src}" "$out"
      chmod +w "$out/plugins"
      ${if needsExternalDeps then ''
        chmod +w "$out/plugins/external_plugin_deps.bzl"
        cp "${src}/external_plugin_deps.bzl" "$out/plugins/external_plugin_deps.bzl"
      '' else ""}
      cp -R "${src}" "$out/plugins/${name}"
      ${builtins.concatStringsSep "" (builtins.map (m: ''
        cp -R "${m.src}" "$out/plugins/${m.name}"
      '') pluginDeps)}
    '';
    bazelTargets = [ "//plugins/${name}" ];
  }).overrideAttrs (prevAttrs: {
    deps = prevAttrs.deps.overrideAttrs (prevDepsAttrs: {
      outputHash = depsOutputHash;
    });
    installPhase = ''
      cp "bazel-bin/plugins/${name}/${name}.jar" "$out"
    '';
  }));
in rec {
  inherit gerrit;
  gerritPlugins = builtins.mapAttrs (name: value: buildGerritPlugin (value // {inherit name;})) rec {
    global-refdb = {
      name = "global-refdb";
      src = pkgs.fetchgit {
        url = "https://gerrit.googlesource.com/modules/global-refdb";
        rev = "7cb71d017038df98889376a4fb837306c9cc7762";
        hash = "sha256-RhZJuyqZ/yRT45CXZP1kcc7E8KhLupWdAe5GLeYQpE4=";
      };
      depsOutputHash = "sha256-Z8PpbyMYOi+0tgtp4RFMa8LGBm302rRX2Vq8cMnpx5Q=";
    };
    zookeeper-refdb = {
      src = pkgs.fetchgit {
        url = "https://gerrit.googlesource.com/plugins/zookeeper-refdb";
        rev = "d5b07d19134fc7884ef969662d5a63365108c07e";
        hash = "sha256-N9JKw05azDlqehUFymnsJlW0ZQe8/9vRlnQgj9hB+Yw=";
      };
      pluginDeps = [ global-refdb ];
      depsOutputHash = "sha256-J1FRJ8MXTeaBZ5S1DRcjUJFRLUny+YzcNzP7xQSpa5A=";
      needsExternalDeps = true;
    };
    events-broker = {
      name = "events-broker";
      src = pkgs.fetchgit {
        url = "https://gerrit.googlesource.com/modules/events-broker";
        rev = "fec27cee2d281e6b22974fe75e73a988b749fdb0";
        hash = "sha256-V4mNGcCy9mfof9K8nYsnEgP/QTe62yukaTQBtaGUEs8=";
      };
      depsOutputHash = "sha256-Z8PpbyMYOi+0tgtp4RFMa8LGBm302rRX2Vq8cMnpx5Q=";
    };
    events-kafka = {
      src = pkgs.fetchgit {
        url = "https://gerrit.googlesource.com/plugins/events-kafka";
        rev = "662887a0b9a9fda91e559a7cbc6d549f66973def";
        hash = "sha256-K8zZXvnuv4yNEBMLR3PGRQk5iS7gCZ1uwXLqzOQrP5g=";
      };
      depsOutputHash = "sha256-4gaW516xVHwpvWyGr6E8uL/uW3HOHe5Dh/FVaaOqnoc=";
      pluginDeps = [ events-broker ];
      needsExternalDeps = true;
    };
    pull-replication = {
      name = "pull-replication";
      src = pkgs.fetchgit {
        url = "https://gerrit.googlesource.com/plugins/pull-replication";
        rev = "e76f10d66bfa08e9b76d11c61aef3f14cd1a53e5";
        hash = "sha256-grQ1vwPcHltQnrGu9/e8pT6jOgxcJ+NkQ/tRnSo0Ls8=";
      };
      pluginDeps = [ events-broker ];
      depsOutputHash = "sha256-UtxMV7fiRlt07cYfrFWdqfGBH6HCO5Pa5E+S1iXcJro=";
    };
    multi-site = {
      src = pkgs.fetchgit {
        url = "https://gerrit.googlesource.com/plugins/multi-site";
        rev = "852cd7b855836310ab25de2d62b14bbc4d514748";
        hash = "sha256-/OzCy6hVrycofCGQX1jLqsXuZ0oNwxb1hpfwHi0U45c=";
      };
      pluginDeps = [ global-refdb events-broker pull-replication ];
      depsOutputHash = "sha256-7Wn7rouOgzZOEubYbpyjok6HBuHWeqM959LaNVL9ZNw=";
    };
    websession-broker = {
      src = pkgs.fetchgit {
        url = "https://gerrit.googlesource.com/plugins/websession-broker";
        rev = "8c44cfb0ac42b394778c92cf6dafe002a245708c";
        hash = "sha256-JvYE1LhGWRu4VAJFcJIW3TbltqB7B3EO3IV2YxiCfFo=";
      };
      pluginDeps = [ events-broker ];
      depsOutputHash = "sha256-Z8PpbyMYOi+0tgtp4RFMa8LGBm302rRX2Vq8cMnpx5Q=";
    };
    healthcheck = {
      src = pkgs.fetchgit {
        url = "https://gerrit.googlesource.com/plugins/healthcheck";
        rev = "9d88dfbe17ad79a96a653a599fc1a0434831723f";
        hash = "sha256-uVg665skNPMTdrkm2GAzk3KINsmtiFzMGD3GEZ0TnKc=";
      };
      depsOutputHash = "sha256-Z8PpbyMYOi+0tgtp4RFMa8LGBm302rRX2Vq8cMnpx5Q=";
    };
    replication-status = {
      src = pkgs.fetchgit {
        url = "https://gerrit.googlesource.com/plugins/replication-status";
        rev = "469efa8c0c75947f0d6157fa05f280477e294bac";
        hash = "sha256-CfSdb+yLq+2mXBkYJA2dOq2ipmyEzBm1R07kRSEh2M0=";
      };
      depsOutputHash = "sha256-Z8PpbyMYOi+0tgtp4RFMa8LGBm302rRX2Vq8cMnpx5Q=";
    };
  };
  gerrit-image = let 
    gerrit-files = pkgs.stdenv.mkDerivation {
      name = "gerrit-init";
      dontUnpack = true;
      nativeBuildInputs = [
        pkgs.bash
        pkgs.jdk17_headless
        pkgs.openssh
        pkgs.git
        pkgs.coreutils
        pkgs.gnugrep
      ];
      installPhase = ''
        mkdir -p $out
        java -jar ${gerrit} init --no-auto-start --skip-all-downloads --batch -d $out/var/gerrit
        rm -rf $out/var/gerrit/{git,db,index,cache,etc}
        ${builtins.concatStringsSep "\n" (builtins.map (p: "p=${p}; cp $p $out/var/gerrit/plugins/\${p#/nix/store/*-}") (builtins.attrValues gerritPlugins))}
        ln -s /var/gerrit/plugins/global-refdb.jar $out/var/gerrit/lib/global-refdb.jar
        ln -s /var/gerrit/plugins/events-broker.jar $out/var/gerrit/lib/events-broker.jar
        ln -s /var/gerrit/plugins/multi-site.jar $out/var/gerrit/lib/multi-site.jar
        ln -s /var/gerrit/plugins/pull-replication.jar $out/var/gerrit/lib/pull-replication.jar
      '';
    };
  in pkgs.dockerTools.buildLayeredImage {
    name = "gerrit-image";
    contents = [
      pkgs.bash
      pkgs.jdk17_headless
      pkgs.openssh
      pkgs.git
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.cgit-pink
      (pkgs.stdenv.mkDerivation {
        name = "gerrit-image-etc";
        dontUnpack = true;
        installPhase = ''
          mkdir -p $out/etc
          cat <<'EOF' > $out/etc/passwd
          gerrit:!:1000:1000:gerrit:/home/gerrit:/bin/bash
          EOF
        '';
      })
    ];
    fakeRootCommands = ''
      cp -r ${gerrit-files}/. .
      chown -R 1000:1000 ./var/gerrit
      find ./var/gerrit -type d -exec chmod +w {} \;
    '';
    config = {
      Volumes = {
        "/home/gerrit" = {};
        "/var/gerrit/tmp" = {};
        "/tmp" = {};
      };
      Env = ["HOME=/home/gerrit"];
      Entrypoint = [(pkgs.stdenv.mkDerivation {
        name = "entrypoint.sh";
        dontUnpack = true;
        installPhase = ''
          cat <<'EOF' > "$out"
          #!/bin/bash
          if [[ ! -d /var/gerrit/git/All-Projects.git ]]; then
          echo "Initializing Gerrit..."
          /lib/openjdk/bin/java -jar /var/gerrit/bin/gerrit.war init --no-auto-start --skip-all-downloads --batch -d /var/gerrit
          fi
          exec /var/gerrit/bin/gerrit.sh run
          EOF
          chmod +x $out
        '';
      })];
    };
  };
}
