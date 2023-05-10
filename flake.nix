{
  inputs = {
    utils.url = "github:ursi/flake-utils";
    purs-nix.url = "github:purs-nix/purs-nix";
    ps-tools.follows = "purs-nix/ps-tools";
    nixpkgs.follows = "purs-nix/nixpkgs";
  };

  outputs = { self, utils, ... }@inputs:
    utils.apply-systems
      {
        inherit inputs;
        make-pkgs = system: import inputs.nixpkgs {
          inherit system;
          # enable ca-derivations globally
          config.contentAddressedByDefault = true;
        };
      }
      ({ pkgs, system, ... }:
        let
          purs-nix = inputs.purs-nix { inherit system; };
          ps = purs-nix.purs
            {
              # Project dir (src, test)
              dir = ./.;
              # Dependencies
              dependencies =
                with purs-nix.ps-pkgs;
                [
                  prelude
                  console
                  effect
                ];
            };
          ps-command = ps.command { };
        in
        {
          packages.default = ps.output { };

          devShells.default =
            pkgs.mkShell
              {
                packages =
                  with pkgs;
                  [
                    ps-command
                    ps-tools.for-0_15.purescript-language-server
                  ];
              };
        });
}
