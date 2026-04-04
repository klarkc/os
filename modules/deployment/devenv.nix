{ config, pkgs, ... }:
{
  packages = with pkgs; [ findutils jq rsync ];

  tasks.install-system = {
    exec = "bash ${config.git.root}/modules/deployment/scripts/install-system.sh";
    input = { host = ""; };
  };

  tasks.update-system = {
    exec = "bash ${config.git.root}/modules/deployment/scripts/update-system.sh";
    input = { host = ""; };
  };

  enterTest = ''
    bash ${config.git.root}/modules/deployment/scripts/install-system.test.sh
    bash ${config.git.root}/modules/deployment/scripts/update-system.test.sh
  '';
}
