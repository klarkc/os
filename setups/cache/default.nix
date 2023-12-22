{ system, pkgs, flake, ... }:
let
  inherit (flake.inputs.everyday.nixosModules) logger host-keys;
  inherit (flake.inputs.disko.nixosModules) disko;
  inherit (flake.outputs.lib) mkSystem secrets;
  agenix = flake.inputs.agenix.nixosModules.default;
  nix-serve = flake.inputs.nix-serve-ng.nixosModules.default;
  domain = "cache.tcp4.me";
  home = "/home/klarkc";
  email = "walkerleite490@gmail.com";
  cache-module = { disks ? [ "/dev/vda" ], config, ... }:
    {
      imports = [
        nix-serve
        agenix
        disko
      ];
      nix.settings.experimental-features = "nix-command flakes";

      # cd secrets
      # nix-store --generate-binary-cache-key cache.tcp4.me ./cache ./cache.pub
      # scp root@cache.tcp4.me:/etc/ssh/ssh_host_ed25519_key.pub cache-vultr.pub
      # cat cache | nix run github:ryantm/agenix -- -e cache.age -i cache-vultr.pub 
      age.secrets.cache.file = "${secrets}/cache.age";
      system.stateVersion = config.system.nixos.version;
      boot.loader.systemd-boot.enable = true;
      # firewall
      networking.firewall.allowedTCPPorts = [
        22
        config.services.nix-serve.port
      ];
      # builders
      nix.settings.trusted-users = [ "builder" ];
      users.users.builder = {
        home = "/home/builder";
        isNormalUser = true;
        openssh. authorizedKeys.keys = [
          (builtins.readFile ../../secrets/builder.pub)
        ];
      };
      # cache service
      services.nix-serve = {
        enable = true;
        secretKeyFile = config.age.secrets.cache.path;
      };
      nix.extraOptions = ''
        min-free = 2684354560
        max-free = 5368709120 
      '';
      # SSH
      services.sshd.enable = true;
      users.users.root.openssh.authorizedKeys.keys = [
        (builtins.readFile ../../secrets/klarkc.pub)
      ];
      # beesd
      services.beesd.filesystems = {
        root = {
          spec = "/";
          hashTableSizeMB = 256;
          extraOptions = [ "--loadavg-target" "2" ];
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
                    extraArgs = [
                      "--label"
                      "root"
                      "-f" # Override existing partition
                    ];
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
      ({ config, modulesPath, lib, ... }: {
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
        # HTTPS web server
        networking.firewall.allowedTCPPorts = [
          22
          80
          443
        ];
        services.nginx.enable = true;
        services.nginx.virtualHosts.${domain} = {
          addSSL = true;
          enableACME = true;
          locations."/".extraConfig = ''
            proxy_pass http://localhost:${builtins.toString config.services.nix-serve.port};
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          '';
        };
        security.acme = {
          acceptTerms = true;
          defaults = { inherit email; };
        };
      })
    ];
  };
}
