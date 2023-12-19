{ system, lib, pkgs, ... }:
let
  inherit (lib) mkSystem mkVirtualMachine;
  inherit (pkgs.lib) mkDefault;
  cache-module = {
    networking = {
      hostName = "cache-os";
      networkmanager.enable = true;
    };
    boot = {
      kernelParams = [
        "copytoram"
        "console=ttyS0,115200"
        "console=tty1"
        "boot.shell_on_fail"
      ];
      loader = {
        timeout = 15;
        grub = {
          enable = true;
          device = "nodev";
          efiSupport = true;
          useOSProber = true;
        };
      };
    };
    fileSystems."/".device = mkDefault "none";
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
