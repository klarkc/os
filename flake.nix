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
      lib = {
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
        # TODO: find a faster way to run vm in devShell
        mkVirtualMachine = efi: name: args: pkgs.writeShellApplication {
          name = "${name}-vm";
          text = ''
            IMG="${name}-efi.img"
            BIOS="${name}-efi-bios.img"
            ARGS="${args}"
            cp -ui --reflink=auto ${pkgs.OVMF.fd}/FV/OVMF.fd "$BIOS"
            chmod a+w "$BIOS"
            cp -ui --reflink=auto ${efi}/nixos.img "$IMG"
            chmod a+w "$IMG"
            qemu-system-${platform} \
              -bios "$BIOS" \
              -drive file="$IMG",format=raw \
              -m 2G \
              $ARGS
          '';
          runtimeInputs = with pkgs; [ qemu ];
        };
      };
      machines = import ./machines { inherit system pkgs lib; };
    in
    {
      nixosConfigurations = {
        inherit (machines.recover) recover-os;
        inherit (machines.cache) cache-os;
      };

      packages.${system} = {
        inherit (machines.recover) recover-efi recover-vm recover-kvm;
        inherit (machines.cache) cache-efi cache-vm cache-kvm;
      };

      devShells.${system}.default =
        pkgs.mkShell
          {
            packages =
              with machines; [
                recover.recover-vm
                recover.recover-kvm
                cache.cache-vm
                cache.cache-kvm
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
