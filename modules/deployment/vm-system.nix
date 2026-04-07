{ host, extraModulePath, root ? ../.. }:
let
  deploymentSystem = import ./nixos-system.nix {
    inherit host root;
    extraModules = [ (import (builtins.toPath extraModulePath)) ];
  };
in { "${host}" = deploymentSystem.config; }
