{ host, extraModules ? [ ], root ? ../.., system ? "x86_64-linux" }:
let
  rootPath = if builtins.isPath root then root else builtins.toPath root;
  sharedModule = rootPath + "/modules/shared/system.nix";
  nixpkgsSrc = builtins.fetchTree {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "9cf7092bdd603554bd8b63c216e8943cf9b12512";
    narHash = "sha256-9tpvMGFteZnd3gRQZFlRCohVpqooygFuy9yjuyRL2C0=";
  };

  diskoSrc = builtins.fetchTree {
    type = "github";
    owner = "nix-community";
    repo = "disko";
    rev = "5ad85c82cc52264f4beddc934ba57f3789f28347";
    narHash = "sha256-PAqwnsBSI9SVC2QugvQ3xeYCB0otOwCacB1ueQj2tgw=";
  };

  machines = import ./machines.nix { inherit root; };
  machineInfo = machines.${host} or (throw "unknown host: ${host}");
  machineImports = machineInfo.nixos.imports or [ ];
  diskoModules = builtins.filter
    (path: builtins.match ".*\\.disko\\.nix" (toString path) != null)
    machineImports;
  nixpkgsLib = import (nixpkgsSrc + "/lib");
  config = nixpkgsLib.nixosSystem {
    system = machineInfo.system or system;
    modules = [ sharedModule ] ++ nixpkgsLib.optionals (diskoModules != [ ])
      [ (import (diskoSrc + "/module.nix")) ]
      ++ [ machineInfo.nixos ({ ... }: { imports = extraModules; }) ];
  };
in {
  inherit config machineInfo;
  hasDisko = builtins.hasAttr "diskoScript" config.config.system.build;
  diskoModule =
    if diskoModules == [ ] then null else builtins.head diskoModules;
  system = config.config.system.build.toplevel;
  diskoScript = config.config.system.build.diskoScript or null;
  imageScript = config.config.system.build.diskoImagesScript or null;
}
