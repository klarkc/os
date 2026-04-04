{ pkgs, ... }:
{
  tasks.update-system.exec = "bash ./modules/update-system/scripts/update-system.sh";

  enterTest = ''
    bash ./modules/update-system/scripts/update-system.test.sh
  '';
}
