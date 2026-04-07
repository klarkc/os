{ config, pkgs, ... }:
let
  vmInstances = builtins.filter (name: config.machines.${name}.nixos != null)
    (builtins.attrNames config.machines);
  vmInstancesText = builtins.concatStringsSep " " vmInstances;

  # Build VM artifacts for each instance
  vmArtifacts = builtins.listToAttrs (builtins.map (instance: {
    name = instance;
    value = import ./vm-system.nix {
      inherit instance;
      host = instance;
      extraModulePath = null; # Will be set at test time
      root = ./.;
    }.${instance};
  }) vmInstances);

  installSystem = pkgs.writeShellApplication {
    name = "install-system";
    runtimeInputs = with pkgs; [
      disko
      findutils
      gnugrep
      gnused
      jq
      nix
      nixos-anywhere
    ];
    text = builtins.readFile ./scripts/install-system.sh;
  };

  updateSystem = pkgs.writeShellApplication {
    name = "update-system";
    runtimeInputs = with pkgs; [ findutils jq nix nixos-rebuild ];
    text = builtins.readFile ./scripts/update-system.sh;
  };

  installSystemTest = pkgs.writeShellApplication {
    name = "install-system-test";
    runtimeInputs = [ installSystem ];
    text = builtins.readFile ./scripts/install-system.test.sh;
  };

  updateSystemTest = pkgs.writeShellApplication {
    name = "update-system-test";
    runtimeInputs = [ updateSystem ];
    text = builtins.readFile ./scripts/update-system.test.sh;
  };

  vmIntegrationTest = pkgs.writeShellApplication {
    name = "vm-integration-test";
    runtimeInputs = with pkgs; [ findutils openssh qemu rsync ];
    text = ''
      export DEVENV_VM_INSTANCES="${vmInstancesText}"
      ${builtins.readFile ./scripts/vm-integration.test.sh}
    '';
  };
in {
  imports = [ ./nixos-deploy.nix ];

  packages = [ updateSystem ];

  outputs = vmArtifacts;

  scripts = {
    install-system.exec = ''${installSystem}/bin/install-system "$@"'';
    install-system-test.exec =
      ''${installSystemTest}/bin/install-system-test "$@"'';
    update-system.exec = ''${updateSystem}/bin/update-system "$@"'';
    update-system-test.exec =
      ''${updateSystemTest}/bin/update-system-test "$@"'';
    vm-integration-test.exec =
      ''${vmIntegrationTest}/bin/vm-integration-test "$@"'';
  };

  tasks."deployment:install-system" = {
    exec = "install-system";
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
    exec = "update-system";
    input = {
      host = "";
      validate_only = false;
    };
  };

  enterTest = ''
    install-system-test
    update-system-test
    vm-integration-test
  '';
}
