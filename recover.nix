{ lib, ... }: {
  users.users.root.password = "";
  users.mutableUsers = false;
  networking.hostName = "recover";
  boot.loader.systemd-boot.enable = true;
  fileSystems."/".device = lib.mkDefault "none";
}
