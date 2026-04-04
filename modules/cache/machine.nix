{ config, lib, pkgs, modulesPath, ... }:
let
  domain = "cache.tcp4.me";
  email = "walkerleite490@gmail.com";
  nixHeuristicGc = lib.attrByPath [ "nix-heuristic-gc" ] null pkgs;
  cacheSecretKey = "/etc/nixos/secrets/cache.key";
in {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  system.stateVersion = config.system.nixos.version;

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd.availableKernelModules =
      [ "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" ];
  };

  nix.settings = {
    trusted-users = [ "builder" ];
    trusted-substituters = [
      "https://${domain}"
      "https://klarkc.cachix.org"
      "https://cache.iog.io"
      "https://cache.zw3rk.com"
      "https://hercules-ci.cachix.org"
      "https://horizon.cachix.org"
    ];
    trusted-public-keys = [
      (builtins.readFile ../../secrets/cache.pub)
      "klarkc.cachix.org-1:R+z+m4Cq0hMgfZ7AQ42WRpGuHJumLLx3k0XhwpNFq9U="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "loony-tools:pr9m4BkM/5/eSTZlkQyRt57Jz7OMBxNSUiMC4FkcNfk="
      "hercules-ci.cachix.org-1:ZZeDl9Va+xe9j+KqdzoBZMFJHVQ42Uu/c/1/KMC5Lw0="
      "horizon.cachix.org-1:MeEEDRhRZTgv/FFGCv3479/dmJDfJ82G6kfUDxMSAw0="
    ];
  };

  nix.extraOptions = ''
    min-free = 2684354560
    max-free = 5368709120
  '';

  users.users.builder = {
    home = "/home/builder";
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../secrets/builder.pub)
      (builtins.readFile ../../secrets/klarkc.pub)
      (builtins.readFile ../../secrets/bridge-service.pub)
    ];
  };

  services.nix-serve = {
    enable = true;
    secretKeyFile = cacheSecretKey;
  };

  systemd.services.nix-gc-ng = lib.mkIf (nixHeuristicGc != null) {
    description = "nix-gc-ng";
    wantedBy = [ "multi-user.target" ];
    requires = [ "nix-daemon.service" ];
    path = [ nixHeuristicGc ];
    script = ''
      available_space=$(df -k --output=avail / | tail -n 1)
      required_space=5114792
      if [ "$available_space" -ge "$required_space" ]; then
        systemd-cat -t nix-gc-ng -p debug echo "Skipping garbage collection, the current available space $available_space is greater than the required space $required_space"
      else
        nix-heuristic-gc $(( (d=required_space-available_space) < 0 ? 0 : d ))K
      fi
    '';
  };

  systemd.timers.nix-gc-ng = lib.mkIf (nixHeuristicGc != null) {
    description = "nix-gc-ng timer";
    wantedBy = [ "multi-user.target" ];
    timerConfig.OnCalendar = "*:0/5";
  };

  services.openssh.enable = true;

  users.users.root.openssh.authorizedKeys.keys =
    [ (builtins.readFile ../../secrets/klarkc.pub) ];

  services.beesd.filesystems = {
    root = {
      spec = "/";
      hashTableSizeMB = 256;
      extraOptions = [ "--loadavg-target" "2" ];
    };
  };

  networking.firewall.allowedTCPPorts =
    [ 22 config.services.nix-serve.port 80 443 ];

  services.nginx = {
    enable = true;
    virtualHosts.${domain} = {
      addSSL = true;
      enableACME = true;
      locations."/".extraConfig = ''
        proxy_pass http://localhost:${
          builtins.toString config.services.nix-serve.port
        };
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults = { inherit email; };
  };

  environment.systemPackages =
    map lib.lowPrio [ pkgs.curl pkgs.gitMinimal pkgs.vim ]
    ++ lib.optional (nixHeuristicGc != null) nixHeuristicGc;
}
