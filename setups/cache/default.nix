{ system, pkgs, flake, ... }:
let
  inherit (flake.inputs.everyday.nixosModules) logger host-keys;
  inherit (flake.outputs.lib) mkSystem secrets;
  agenix = flake.inputs.agenix.nixosModules.default;
  nix-serve = flake.inputs.nix-serve-ng.nixosModules.default;
  domain = "cache.64-b.it";
  home = "/home/klarkc";
  cache-module = { config, ... }:
    {
      imports = [ logger nix-serve agenix ];
      # cd secrets
      # nix-store --generate-binary-cache-key cache.64-b.it ./cache ./cache.skey
      # cat cache | nix run github:ryantm/agenix -- -e cache.age -i ~/.ssh/id_ed25519
      # cp ~/.ssh/id_ed25519.pub klarkc.pub
      age.secrets.cache.file = "${secrets}/cache.age";
      system.stateVersion = config.system.nixos.version;
      fileSystems."/".device = "none";
      boot.loader.grub.device = "nodev";
      services = {
        sshd.enable = true;
        nix-serve = {
          enable = true;
          secretKeyFile = config.age.secrets.cache.path;
        };
      };
      users = {
        users.klarkc = {
          isNormalUser = true;
          inherit home;
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = [
            (builtins.readFile ../../secrets/klarkc.pub)
          ];
        };
        mutableUsers = false;
      };
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
    };
in
rec {
  modules.cache = cache-module;

  packages.cache-vm = mkSystem {
    modules = with modules; [
      cache
      ({ config, ... }:
        let inherit (config.services.nix-serve) port; in
        {
          imports = [ host-keys ];
          host-keys.source = "${home}/.ssh";
          virtualisation.forwardPorts = [
            { from = "host"; host.port = 2222; guest.port = 22; }
            { from = "host"; host.port = port; guest.port = port; }
          ];
        })
    ];
    format = "vm-nogui";
  };

  machines.cache_0 = mkSystem {
    modules = with modules; [
      cache
      {
        networking.hostName = "cache_0";
      }
    ];
  };
}
