{
  inputs = {
    utils.url = "github:ursi/flake-utils";
    purs-nix.url = "github:purs-nix/purs-nix";
    purenix.url = "github:purenix-org/purenix";
    ps-tools.follows = "purs-nix/ps-tools";
    nixpkgs.follows = "purs-nix/nixpkgs";
  };

  outputs = { self, utils, ... }@inputs:
    utils.apply-systems { inherit inputs; }
      ({ pkgs, system, purenix, ... }:
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
          ps-command = ps.command { };
          ps-output = ps.output { };
          os = pkgs.stdenv.mkDerivation
            {
              name = "os";
              src = ps-output;
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
                    ps-command
                    ps-tools.for-0_15.purescript-language-server
                  ];
              };
        });
}
