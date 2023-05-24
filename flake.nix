{
  inputs = {
    utils.url = "github:ursi/flake-utils";
    purs-nix.url = "github:purs-nix/purs-nix";
    purenix.url = "github:purenix-org/purenix";
    ps-tools.follows = "purs-nix/ps-tools";
    nixpkgs.follows = "purs-nix/nixpkgs";
  };

  outputs = { self, utils, ... }@inputs:
    let
      # TODO add missing arm to match standard systems
      #  right now purs-nix is only compatible with x86_64-linux
      systems = [ "x86_64-linux" ];
    in
    utils.apply-systems { inherit inputs systems; }
      ({ pkgs, system, purenix, ps-tools, ... }:
        let
          purs-nix = inputs.purs-nix
            {
              inherit system;
              defaults.compile.codegen = "corefn";
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
          os = pkgs.stdenv.mkDerivation
            {
              name = "os";
              src = ps.output { };
              nativeBuildInputs = with pkgs; [ purenix ];
              dontInstall = true;
              prefix = "output";
              postBuild = ''
                mkdir -p $out
                cp -L -r $src $out/output
                chmod -R u+w $out/output
                cd $out
                purenix
              '';
            };

        in
        {
          packages.default = os;
          devShells.default =
            pkgs.mkShell
              {
                packages =
                  with pkgs;
                  [
                    ps-tools.for-0_15.purescript-language-server
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
