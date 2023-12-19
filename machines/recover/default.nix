{ system, pkgs, flake, ... }:
let
  inherit (pkgs.lib) mkDefault;
  inherit (flake.outputs.lib) mkSystem mkVirtualMachine;
  recover-module = {
    nix = {
      extraOptions = ''
        experimental-features = nix-command flakes repl-flake
      '';
    };
    nixpkgs.config.allowUnfree = true;
    hardware.enableAllFirmware = true;
    users = {
      users.recover = {
        password = "recover";
        isNormalUser = true;
        home = "/home/recover";
        description = "Recover";
        extraGroups = [ "wheel" "networkmanager" ];
      };
      mutableUsers = false;
    };
    networking = {
      hostName = "recover-os";
      networkmanager.enable = true;
    };
    boot = {
      kernelParams = [
        "copytoram"
        "console=ttyS0,115200"
        "console=tty1"
        "boot.shell_on_fail"
      ];
      supportedFilesystems = [
        "btrfs"
        "exfat"
        "ext2"
        "ext4"
        "ntfs"
        "vfat"
      ];
      loader = {
        timeout = 15;
        grub = {
          enable = true;
          device = "nodev";
          efiSupport = true;
          useOSProber = true;
          memtest86.enable = true;
        };
      };
    };
    fileSystems."/".device = mkDefault "none";

    environment.systemPackages = with pkgs; [
      btop
      coreutils
      curl
      ddrescue
      efibootmgr
      efivar
      findutils
      gnugrep
      gnused
      gnutar
      gptfdisk
      hdparm
      inetutils
      less
      lsof
      parted
      pciutils
      ripgrep
      rsync
      sdparm
      smartmontools
      sshfs
      time
      testdisk
      unzip
      usbutils
      wget
      which
      zip
      ntfs3g
      f2fs-tools
      jfsutils
      nilfs-utils
      reiserfsprogs
      xfsprogs
      xfsdump
      gparted
    ];

    services = {
      openssh.enable = true;

      xserver = {
        enable = true;
        windowManager.xmonad.enable = true;
        displayManager = {
          defaultSession = "none+xmonad";
          autoLogin = {
            enable = true;
            user = "recover";
          };
        };
      };
    };

    programs = {
      tmux.enable = true;
      neovim = {
        enable = true;
        viAlias = true;
        vimAlias = true;
      };
      mtr.enable = true;
      htop.enable = true;
    };
  };
in
rec {
  recover-os = mkSystem {
    inherit system;
    modules = [ recover-module ];
  };

  recover-efi = mkSystem {
    inherit system;
    modules = [ recover-module ];
    format = "raw-efi";
  };

  recover-vm = mkVirtualMachine recover-efi "recover" "";

  recover-kvm = mkVirtualMachine recover-efi "recover" "--enable-kvm";
}
