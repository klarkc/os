{ lib, pkgs, ... }: {
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "memtest86-efi"
  ];
  users = {
    users.root.password = "";
    mutableUsers = false;
  };
  networking = {
    hostName = "recover";
    networkmanager.enable = true;
  };
  boot = {
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

  systemd.services.firstboot.enable = true;

  environment.systemPackages = with pkgs; [
    ddrescue
    btop
    parted
  ];

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "without-password";
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
