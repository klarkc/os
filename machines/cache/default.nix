{ system, pkgs, flake, ... }:
let
  inherit (pkgs.lib) mkDefault;
  inherit (flake.inputs.everyday.nixosModules) logger;
  inherit (flake.inputs.attic.nixosModules) atticd;
  inherit (flake.outputs.lib) mkSystem mkVirtualMachine;
  domain = "cache.klarkc.is-a.dev";
  cache-module = { config, ... }: {
    imports = [ logger atticd ];
    networking = {
      hostName = "cache-os";
      networkmanager.enable = true;
    };
    boot = {
      kernelParams = [
        "console=ttyS0,115200"
        "console=tty1"
      ];
      loader.grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        useOSProber = true;
      };
    };
    fileSystems."/".device = mkDefault "none";

    services.atticd = {
      enable = true;
      # echo -n 'ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64="' > /tmp/atticd.env
      # openssl rand 64 | base64 -w0 >> /tmp/atticd.env
      # echo -n '"' >> /tmp/atticd.env
      credentialsFile = "/tmp/atticd.env";
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
    # Web server
    services.nginx = {
      virtualHosts.${domain} = {
        forceSSL = true;
        enableACME = true;
        locations."/".extraConfig = ''
          proxy_pass http://localhost:8080;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
      };
    };
  };
in
rec {
  cache-os = mkSystem {
    inherit system;
    modules = [ cache-module ];
  };

  cache-efi = mkSystem {
    inherit system;
    modules = [ cache-module ];
    format = "raw-efi";
  };

  cache-vm = mkVirtualMachine cache-efi "cache" "--nographic";

  cache-kvm = mkVirtualMachine cache-efi "cache" "--nographic --enable-kvm";
}
