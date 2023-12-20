{ system, pkgs, flake, ... }:
let
  inherit (flake.inputs.generators.nixosModules) vm-nogui;
  inherit (flake.inputs.everyday.nixosModules) logger host-keys;
  inherit (flake.inputs.attic.nixosModules) atticd;
  inherit (flake.outputs.lib) mkSystem secrets;
  agenix = flake.inputs.agenix.nixosModules.default;
  domain = "cache.klarkc.is-a.dev";
  home = "/home/klarkc";
  port = 8080;
  cache-module = { config, ... }: {
    imports = [ logger atticd vm-nogui agenix host-keys ];
    # cd secrets
    # echo -n 'ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64="' > env
    # openssl rand 64 | base64 -w0 >> env
    # echo -n '"' >> env
    # cat env | nix run github:ryantm/agenix -- -e env.age -i ~/.ssh/id_ed25519
    # cp ~/.ssh/id_ed25519.pub klarkc.pub
    age.secrets.env.file = "${secrets}/env.age";
    services.atticd.credentialsFile = config.age.secrets.env.path;
    host-keys.source = "${home}/.ssh";
    system.stateVersion = config.system.nixos.version;
    fileSystems."/".device = "none";
    boot.loader.grub.device = "nodev";
    services.atticd = {
      enable = true;
      settings = {
        listen = "[::]:8080";
        chunking = {
          nar-size-threshold = 64 * 1024; # 64 KiB
          min-size = 16 * 1024; # 16 KiB
          avg-size = 64 * 1024; # 64 KiB
          max-size = 256 * 1024; # 256 KiB
        };
      };
    };
    networking.firewall.allowedTCPPorts = [
      80
      port
    ];
    virtualisation.forwardPorts = [
      { from = "host"; host.port = port; guest.port = port; }
    ];
    # Web server
    services.nginx = {
      virtualHosts.${domain} = {
        forceSSL = true;
        enableACME = true;
        locations."/".extraConfig = ''
          proxy_pass http://localhost:${port};
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
    modules = with modules; [ cache ];
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
