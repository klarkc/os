{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    generators.url = "github:nix-community/nixos-generators";
    agenix.url = "github:ryantm/agenix";
    nix-serve-ng.url = github:aristanetworks/nix-serve-ng;
    everyday.url = "github:klarkc/nixos-everyday";
    disko.url = "github:nix-community/disko";
    # optimizations
    generators.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    nix-serve-ng.inputs.nixpkgs.follows = "nixpkgs";
    disko.inputs.nixpkgs.follows = "nixpkgs"; 
  };

  outputs = { self, ... }@inputs:
    let
      # TODO add cross-platform build
      platform = "x86_64";
      os = "linux";
      system = "${platform}-${os}";
      pkgs = import inputs.nixpkgs { inherit system; };
      lib = {
        secrets = ./secrets;
        mkSystem = options:
          let
            inherit (inputs.nixpkgs.lib) nixosSystem;
            inherit (inputs.generators) nixosGenerate;
            inherit (builtins) hasAttr;
            finalOptions = options // { inherit system; };
          in
          if hasAttr "format" options then
            nixosGenerate finalOptions
          else
            nixosSystem finalOptions;
      };
      setups = import ./setups {
        inherit system pkgs;
        flake = self;
      };
    in
    {
      inherit lib;

      nixosModules = {
        inherit (setups.recover.modules) recover;
        inherit (setups.cache.modules) cache-module;
      };

      nixosConfigurations = {
        inherit (setups.recover.machines) recover_0;
        inherit (setups.cache.machines) cache-vultr;
      };

      packages.${system} = {
        inherit (setups.recover.packages) recover-efi recover-vm;
        inherit (setups.cache.packages) cache-vm;
      };
    };

  # --- Flake Local Nix Configuration ----------------------------
  nixConfig = {
    extra-experimental-features = "nix-command flakes";
    # This sets the flake to use nix cache.
    # Nix should ask for permission before using it,
    # but remove it here if you do not want it to.
    extra-substituters = [
      "https://klarkc.cachix.org?priority=99"
      "https://cache.nixos.org"
    ];
    extra-trusted-public-keys = [
      "klarkc.cachix.org-1:R+z+m4Cq0hMgfZ7AQ42WRpGuHJumLLx3k0XhwpNFq9U="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };
}
