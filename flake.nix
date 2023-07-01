{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    generators.url = "github:nix-community/nixos-generators";
  };

  outputs = { self, ... }@inputs:
    let
      # TODO add cross-platform build
      platform = "x86_64";
      os = "linux";
      system = "${platform}-${os}";
      pkgs = import inputs.nixpkgs { inherit system; };
      mkSystem = options:
        let
          inherit (inputs.nixpkgs.lib) nixosSystem;
          inherit (inputs.generators) nixosGenerate;
          inherit (builtins) hasAttr;
        in
        if hasAttr "format" options then
          nixosGenerate options
        else
          nixosSystem options;
      recover = mkSystem {
        inherit system;
        modules = [ ./recover.nix ];
      };

      recover-efi = mkSystem {
        inherit system;
        modules = [ ./recover.nix ];
        format = "raw-efi";
      };

      # TODO: find a faster way to run recover in devShell
      recover-vm = pkgs.writeShellApplication {
        name = "recover-vm";
        text = ''
          TMPD=$(mktemp -d)
          echo "$TMPD"
          IMG="$TMPD/recover-efi.img"
          BIOS="$TMPD/recover-efi-bios.img"
          cp -ui --reflink=auto ${pkgs.OVMF.fd}/FV/OVMF.fd "$BIOS"
          chmod a+w "$BIOS"
          cp -ui --reflink=auto ${recover-efi}/nixos.img "$IMG"
          chmod a+w "$IMG"
          qemu-system-${platform} \
            -nographic \
            -bios "$BIOS" \
            -drive file="$IMG",format=raw \
            -m 2G
          rm -Rf "$TMPD"
        '';
        runtimeInputs = with pkgs; [ tree rsync qemu ];
      };
    in
    {
      nixosConfigurations = {
        inherit recover;
      };

      packages.${system} = {
        inherit recover-efi recover-vm;
      };

      devShells.${system}.default =
        pkgs.mkShell
          {
            packages =
              [
                recover-vm
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
