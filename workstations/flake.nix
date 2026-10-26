{
  description = "Disposable Dell thin client and CPU-only GCE NixOS workstation";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      mk = modules: nixpkgs.lib.nixosSystem { inherit system modules; };
      isoModule = { modulesPath, ... }: {
        imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];
        isoImage.isoName = "solo-thin-client-x86_64.iso";
      };
      gceModule = { modulesPath, ... }: {
        imports = [ (modulesPath + "/virtualisation/google-compute-image.nix") ];
      };
    in
    {
      nixosConfigurations.thin-client = mk [ isoModule ./thin-client.nix ];
      nixosConfigurations.gcp-workstation = mk [ gceModule ./gcp-workstation.nix ];

      packages.${system} = {
        thin-client-iso = self.nixosConfigurations.thin-client.config.system.build.isoImage;
        gce-image = self.nixosConfigurations.gcp-workstation.config.system.build.googleComputeImage;
      };

      checks.${system} = {
        # Boots BOTH client and server in disposable QEMU VMs, not merely
        # evaluating a Nix expression. No credentials or cloud resources.
        ventoy-usb-persistence-vm = import ./tests/ventoy-persistence.nix { inherit pkgs; };

        boot-and-network-vm = pkgs.testers.runNixOSTest {
          name = "solo-thin-client-and-workstation";
          nodes = {
            client = { lib, ... }: {
              imports = [ ./thin-client.nix ];
              users.users.nixos = {
                isNormalUser = true;
                extraGroups = [ "wheel" "networkmanager" "video" ];
                initialPassword = "test-only";
              };
              security.sudo.wheelNeedsPassword = true;
              # Real USB devices are intentionally absent; persistence must
              # fail closed instead of touching an internal VM disk.
              virtualisation.memorySize = 2048;
              virtualisation.graphics = true;
              services.xserver.videoDrivers = [ "modesetting" ];
              system.stateVersion = "26.05";
            };
            server = { lib, ... }: {
              imports = [ ./gcp-workstation.nix ];
              # The production image uses GCE OS Login for SSH.
              # Here only exercise native services in a normal VM.
              virtualisation.memorySize = 2048;
              virtualisation.graphics = true;
              system.stateVersion = "26.05";
            };
          };
          testScript = ''
            start_all()
            client.wait_for_unit("multi-user.target")
            server.wait_for_unit("multi-user.target")
            client.succeed("systemctl is-active NetworkManager.service")
            client.succeed("test -e /run/current-system/sw/bin/solo-gce-iap")
            client.succeed("test -e /run/current-system/sw/bin/gcloud")
            client.succeed("! test -e /run/current-system/sw/bin/solo-client-wg")
            client.succeed("! test -e /run/current-system/sw/bin/solo-gce-endpoint")
            client.succeed("! systemctl is-active --quiet tailscaled.service")
            client.succeed("systemctl show -P Result solo-ventoy-state.service | grep -Fx success")
            client.succeed("test -e /run/current-system/sw/bin/solo-client-state")
            client.succeed("test -e /run/current-system/sw/bin/xfreerdp")
            client.succeed("! mountpoint -q /run/solo-client/ventoy")
            client.succeed("test ! -d /run/solo-client/ventoy/solo-client")
            client.succeed("! test -e /home/nixos/.config/solo-gcloud/credentials.db")
            client.succeed("systemctl start solo-save-state.service")
            server.succeed("systemctl is-active xrdp.service")
            server.succeed("systemctl is-active xrdp-sesman.service")
            # Server is managed independently by BuildGCE. Do not assert
            # its legacy Tailscale status as part of the client contract.
            server.succeed("id klarkc")
            server.succeed("test -d /home/klarkc")
            server.succeed("ss -lnt | grep ':3389'")
          '';
        };
      };
    };
}
