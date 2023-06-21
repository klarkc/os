{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    microvm.url = "github:astro/microvm.nix";
  };

  outputs = { self, ... }@inputs:
    let
      # TODO add cross-platform build
      system = "x86_64-linux";
      pkgs = import inputs.nixpkgs { inherit system; };
      nixosConfigurations = self.packages.${system};
      networking = import ./networking.nix;
      users = import ./users.nix;
      mkSystem = options:
        let 
          inherit (inputs.nixpkgs.lib) nixosSystem;
          inherit (builtins) removeAttrs;
          unmakeOverridable = r: removeAttrs r [
            "override"
            "overrideDerivation"
          ];
        in nixosSystem (unmakeOverridable options);
      systemOptions =
          let
            inherit (pkgs.lib) makeOverridable; 
            inherit (pkgs.lib.trivial) id;
          in pkgs.lib.makeOverridable id 
          {
              inherit system;
              modules =
                [
                  networking
                  users
                ];
          };
      recover = mkSystem systemOptions;
      recover-vm = mkSystem systemOptions.override {
        modules = systemOptions.modules ++ [
          inputs.microvm.nixosModules.microvm
        ];
      };
    in
    {
      nixosConfigurations = {
        inherit recover;
      };

      packages.${system} = {
        inherit recover;
      };

      devShells.${system}.default =
        pkgs.mkShell
          {
            packages =
              let
                inherit (recover-vm.config.microvm.runner) qemu;
              in
              with pkgs;
              [
                # adds microvm-*
                qemu
              ];

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
