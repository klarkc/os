{ config, pkgs, ... }:
{
  system.stateVersion = "24.05";

  networking.hostName = "ssdinarch";

  users.users.user = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    password = "password";
  };

  services.openssh.enable = true;
  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [ git vim ];
}
