{ pkgs, ... }:
{
  packages = with pkgs; [
    git
  ];

  languages = {
    nix.enable = true;
    shell.enable = true;
  };

  git-hooks.hooks = {
    deadnix.enable = true;
    nil.enable = true;
    nixfmt-classic.enable = true;
    shellcheck.enable = true;
  };
}
