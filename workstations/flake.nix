{
  description = "Disposable Dell thin client and CPU-only GCE NixOS workstation";

  # Matches the current klarkc/dotfiles nixpkgs lock to reduce rebuilds.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      mk = modules: nixpkgs.lib.nixosSystem { inherit system modules; };
    in
    {
      nixosConfigurations.thin-client = mk [
        ({ modulesPath, ... }: {
          imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];
        })
        ./thin-client.nix
      ];

      nixosConfigurations.gcp-workstation = mk [
        ({ modulesPath, ... }: {
          imports = [ (modulesPath + "/virtualisation/google-compute-image.nix") ];
        })
        ./gcp-workstation.nix
      ];

      packages.${system} = {
        thin-client-iso = self.nixosConfigurations.thin-client.config.system.build.isoImage;
        gce-image = self.nixosConfigurations.gcp-workstation.config.system.build.googleComputeImage;
      };
    };
}
