{
  description = "This is my brand new attempt to use NixOS as my personal OS.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    utils.url = "github:ursi/flake-utils";
    purs-nix.url = "github:purs-nix/purs-nix";
    purenix.url = "github:purenix-org/purenix";
    ps-tools.follows = "purs-nix/ps-tools";
    microvm.url = "github:astro/microvm.nix";
  };

  outputs = { self, utils, ... }@inputs:
    let
      # TODO add missing arm to match standard systems
      #  right now purs-nix is only compatible with x86_64-linux
      system = "x86_64-linux";
      systems = [ system ];
      nixosConfigurations.default = self.packages.${system}.default;
    in
    utils.apply-systems
      { inherit inputs systems; }
      ({ pkgs, system, purenix, ps-tools, ... }@ctx:
        let
          compile = { codegen = "corefn"; };
          purs-nix = inputs.purs-nix
            {
              inherit system;
              defaults = { inherit compile; };
            };
          ps = purs-nix.purs
            {
              # Project dir (src, test)
              dir = ./.;
              # Dependencies
              dependencies =
                [
                  # FIXME use prelude from purenix
                  "prelude"
                ];
            };
          prefix = "output";
          Main = import (pkgs.stdenv.mkDerivation
            {
              inherit prefix;
              name = "Main";
              src = ps.output { };
              nativeBuildInputs = with pkgs; [ purenix ];
              dontInstall = true;
              postBuild = ''
                mkdir -p $out
                cp -L -r $src $out/${prefix}
                chmod -R u+w $out/${prefix}
                cd $out
                purenix
              '';
            } + "/${prefix}/Main");
          os = Main.main inputs ctx;
        in
        {
          packages.default = os.config.microvm.runner.qemu;
          devShells.default =
            pkgs.mkShell
              {
                packages =
                  with pkgs;
                  [
                    (ps.command { inherit compile; })
                    ps-tools.for-0_15.purescript-language-server
                    ps-tools.for-0_15.purty
                  ];
              };
        });

  # --- Flake Local Nix Configuration ----------------------------
  nixConfig = {
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
