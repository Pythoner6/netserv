{pkgs}: let 
  versions = {
    "v1.29.0" = "sha256-M0zdXmTfyykNtzkQu1D/+DWAoeOWOpLS7Qy6UFT6/Ns=";
  };
in {
  vendor-k8s = k8s-version: pkgs.buildGoModule {
    name = "vendor-k8s";
    src = ./cue-k8s-go + "/${k8s-version}";
    nativeBuildInputs = with pkgs; [ cue ];
    vendorHash = versions."${k8s-version}";
    buildPhase = ''
      cue get go k8s.io/api/...
      cue get go k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1
    '';
    installPhase = ''
      mkdir $out
      cp -a cue.mod/gen/. $out
    '';
  };
}
