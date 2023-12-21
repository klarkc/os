{ system, pkgs, flake, ... }:
let
  inherit (flake.inputs.everyday.nixosModules) logger host-keys;
  inherit (flake.inputs.disko.nixosModules) disko;
  inherit (flake.outputs.lib) mkSystem secrets;
  agenix = flake.inputs.agenix.nixosModules.default;
  nix-serve = flake.inputs.nix-serve-ng.nixosModules.default;
  domain = "cache.64-b.it";
  home = "/home/klarkc";
  authorizedKeys.keys = [
    (builtins.readFile ../../secrets/klarkc.pub)
  ];
  cache-module = { disks ? [ "/dev/vda" ], config, ... }:
    {
      imports = [
        nix-serve
        agenix
        disko
      ];
      # cd secrets
      # nix-store --generate-binary-cache-key cache.64-b.it ./cache ./cache.skey
      # cat cache | nix run github:ryantm/agenix -- -e cache.age -i ~/.ssh/id_ed25519
      # cp ~/.ssh/id_ed25519.pub klarkc.pub
      age.secrets.cache.file = "${secrets}/cache.age";
      system.stateVersion = config.system.nixos.version;
      boot.loader.systemd-boot.enable = true;
      services = {
        sshd.enable = true;
        nix-serve = {
          enable = true;
          secretKeyFile = config.age.secrets.cache.path;
        };
      };
      users.users.root.openssh = { inherit authorizedKeys; };
      networking.firewall.enable = false;
      # Web server
      services.nginx = {
        virtualHosts.${domain} = {
          forceSSL = true;
          enableACME = true;
          locations."/".extraConfig = ''
            proxy_pass http://localhost:${config.services.nix-serve.port};
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          '';
        };
      };
      # disko
      disko.devices = {
        disk = {
          vdb = {
            type = "disk";
            device = builtins.elemAt disks 0;
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  priority = 1;
                  name = "ESP";
                  start = "1M";
                  end = "128M";
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                  };
                };
                root = {
                  size = "100%";
                  content = {
                    type = "btrfs";
                    extraArgs = [ "-f" ]; # Override existing partition
                    # Subvolumes must set a mountpoint in order to be mounted,
                    # unless their parent is mounted
                    subvolumes = {
                      # Subvolume name is different from mountpoint
                      "/rootfs" = {
                        mountpoint = "/";
                      };
                      # Parent is not mounted so the mountpoint must be set
                      "/nix" = {
                        mountOptions = [ "compress=zstd" "noatime" ];
                        mountpoint = "/nix";
                      };
                      # Subvolume for the swapfile
                      "/swap" = {
                        mountpoint = "/.swapvol";
                        swap.swapfile.size = "1024M";
                      };
                    };

                    mountpoint = "/partition-root";
                  };
                };
              };
            };
          };
        };
      };
    };
in
rec {
  modules = { inherit cache-module; };

  packages.cache-vm = mkSystem {
    modules = with modules; [
      cache-module
      ({ config, ... }:
        let inherit (config.services.nix-serve) port; in
        {
          imports = [
            logger
            # TODO: modulesPath should be available
            # (modulesPath + "/profiles/qemu-guest.nix")
            host-keys
          ];
          host-keys.source = "${home}/.ssh";
          virtualisation.forwardPorts = [
            { from = "host"; host.port = 2222; guest.port = 22; }
            { from = "host"; host.port = port; guest.port = port; }
          ];
        })
    ];
    format = "vm-nogui";
  };

  machines.cache-vultr = mkSystem {
    modules = with modules; [
      cache-module
      ({ modulesPath, lib, ... }: {
        _module.args.disks = [ "/dev/vda" ];
        imports = [
          (modulesPath + "/profiles/qemu-guest.nix")
          (modulesPath + "/installer/scan/not-detected.nix")
        ];
        networking.hostName = "cache-vultr";
        boot = {
          loader.efi.canTouchEfiVariables = true;
          initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" ];
        };
        environment.systemPackages = map lib.lowPrio [
          pkgs.curl
          pkgs.gitMinimal
        ];
      })
    ];
  };
}
