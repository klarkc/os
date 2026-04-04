{ pkgs, ... }:
{
  tasks.install-system.exec = "bash ./modules/install-system/scripts/install-system.sh";

  enterTest = ''
    bash ./modules/install-system/scripts/install-system.test.sh
  '';
}
