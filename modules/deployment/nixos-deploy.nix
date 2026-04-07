{ config, lib, inputs, ... }:

let
  cfg = config.devenv.deployment;
  sharedModule = ../shared/system.nix;
  machineNames = builtins.filter (name: config.machines.${name}.nixos != null)
    (builtins.attrNames config.machines);

  outputAttrs = builtins.concatMap (host:
    let
      machine = config.machines.${host};
      machineImports = machine.nixos.imports or [ ];
      hasDiskoModule =
        builtins.any (path: lib.hasSuffix ".disko.nix" (toString path))
        machineImports;
      nixosConfig = inputs.nixpkgs.lib.nixosSystem {
        system = machine.system;
        modules = [ sharedModule ] ++ lib.optional hasDiskoModule (import
          ((builtins.fetchTree {
            type = "github";
            owner = "nix-community";
            repo = "disko";
            rev = "5ad85c82cc52264f4beddc934ba57f3789f28347";
            narHash = "sha256-PAqwnsBSI9SVC2QugvQ3xeYCB0otOwCacB1ueQj2tgw=";
          }) + "/module.nix")) ++ [ machine.nixos ];
      };

      outputs = {
        "${host}" = nixosConfig.config.system.build.toplevel;
      } // lib.optionalAttrs
        (lib.hasAttrByPath [ "config" "system" "build" "diskoScript" ]
          nixosConfig) {
            "${host}-disko-script" =
              nixosConfig.config.system.build.diskoScript;
          } // lib.optionalAttrs
        (lib.hasAttrByPath [ "config" "system" "build" "diskoImagesScript" ]
          nixosConfig) {
            "${host}-image-script" =
              nixosConfig.config.system.build.diskoImagesScript;
          };
    in builtins.map (name: {
      inherit name;
      value = outputs.${name};
    }) (builtins.attrNames outputs)) machineNames;
in {
  options.devenv.deployment = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic NixOS deployment outputs";
    };
  };

  config = lib.mkIf cfg.enable { outputs = lib.listToAttrs outputAttrs; };
}
