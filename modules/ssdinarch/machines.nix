{
  "ssdinarch-0" = {
    system = "x86_64-linux";
    nixos.imports = [ ./ssdinarch-0.nix ./ssdinarch-0.disko.nix ];
  };
}
