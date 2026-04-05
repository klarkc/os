{ config, pkgs, ... }: {
  packages = with pkgs; [
    disko
    findutils
    jq
    nixos-anywhere
    nixos-rebuild
    openssh
    qemu
    rsync
  ];

  tasks."deployment:install-system" = {
    exec =
      "bash ${config.git.root}/modules/deployment/scripts/install-system.sh";
    input = {
      host = "";
      target_ssh = "";
      target_port = "";
      target_disk = "";
      target_image = "";
      validate_only = false;
    };
  };

  tasks."deployment:update-system" = {
    exec =
      "bash ${config.git.root}/modules/deployment/scripts/update-system.sh";
    input = {
      host = "";
      validate_only = false;
    };
  };

  enterTest = ''
    bash ${config.git.root}/modules/deployment/scripts/install-system.test.sh
    bash ${config.git.root}/modules/deployment/scripts/update-system.test.sh
    bash ${config.git.root}/modules/deployment/scripts/vm-integration.test.sh
  '';
}
