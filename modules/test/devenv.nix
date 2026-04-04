{ pkgs, ... }:
{
  packages = with pkgs; [ bash coreutils findutils gnugrep gnused rsync git shellcheck ];

  enterTest = ''
    bash ./modules/test/scripts/run-tests.sh
  '';
}
