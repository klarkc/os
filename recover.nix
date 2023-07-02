{ lib, pkgs, ... }: {
  hardware.enableAllFirmware = true;
  nixpkgs.config.allowUnfree = true;
  users = {
    users.root.password = "root";
    mutableUsers = false;
  };
  networking = {
    hostName = "recover";
    networkmanager.enable = true;
  };
  boot = {
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
  fileSystems."/".device = lib.mkDefault "none";

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
    time
    testdisk
    unzip
    usbutils
    wget
    which
    zip
  ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
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
}
