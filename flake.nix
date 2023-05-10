{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    purifix.url = "github:purifix/purifix";
  };

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ inputs.purifix.overlay ];
      };
      os = pkgs.purifix {
        src = ./.;
      };
    in
    {
      packages.default = os;
    });
}
