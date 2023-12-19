{ system, pkgs, flake, ... }:
let
  inherit (pkgs.lib) mkDefault version;
  inherit (flake.outputs.lib) mkSystem;
  recover-module = { config, ... }: {
    system.stateVersion = config.system.nixos.version;
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
    networking.networkmanager.enable = true;
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
  modules.recover = recover-module;

  packages = {
    recover-efi = mkSystem {
      modules = with modules; [ recover ];
      format = "raw-efi";
    };

    recover-vm = mkSystem {
      modules = with modules; [ recover ];
      format = "vm-nogui";
    };
  };

  machines.recover_0 = mkSystem {
    modules = with modules; [
      recover
      {
        networking.hostName = "recover_0";
      }
    ];
  };
}
