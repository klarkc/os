{ pkgs, ... }: {
  networking.hostName = "ssdinarch-0";
  system.stateVersion = "24.05";

  users.users.user = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    password = "password";
  };

  services.openssh.enable = true;
  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [ git vim ];
}
