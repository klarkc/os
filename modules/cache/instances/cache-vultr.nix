{ ... }: {
  imports = [ ../machine.nix ];

  networking.hostName = "cache-vultr";
}
