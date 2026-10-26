{ pkgs }:

pkgs.testers.runNixOSTest {
  name = "solo-gce-workstation-security";
  nodes.server = { lib, ... }: {
    imports = [ ../gcp-workstation.nix ];
    virtualisation.memorySize = 3072;
    virtualisation.graphics = true;
    system.stateVersion = "26.05";
  };
  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("xrdp.service")
    server.wait_for_unit("xrdp-sesman.service")
    server.wait_for_unit("tailscaled.service")
    server.wait_for_unit("sshd.service")
    server.succeed("id klarkc")
    server.succeed("test -d /home/klarkc")
    server.succeed("test -e /run/current-system/sw/bin/git")
    server.succeed("ss -lnt | grep ':3389'")
    # Inspect the generated config used by the active daemon and its syntax.
    # The upstream sshd -T returned an empty listing on this VM runner.
    server.succeed("${pkgs.openssh}/bin/sshd -t -f /etc/ssh/sshd_config")
    server.succeed("grep -Eqi '^[[:space:]]*PasswordAuthentication[[:space:]]+no[[:space:]]*
    server.succeed("test -e /run/current-system/sw/bin/tailscale")
    server.succeed("test -e /run/current-system/sw/bin/xfce4-session")
    server.succeed("getent passwd klarkc | grep '^klarkc:'")
    server.succeed("test ! -e /home/klarkc/.git")
  '';
}
 /etc/ssh/sshd_config")
    server.succeed("grep -Eqi '^[[:space:]]*PermitRootLogin[[:space:]]+prohibit-password[[:space:]]*
    server.succeed("test -e /run/current-system/sw/bin/tailscale")
    server.succeed("test -e /run/current-system/sw/bin/xfce4-session")
    server.succeed("getent passwd klarkc | grep '^klarkc:'")
    server.succeed("test ! -e /home/klarkc/.git")
  '';
}
 /etc/ssh/sshd_config")
    server.succeed("test -e /run/current-system/sw/bin/tailscale")
    server.succeed("test -e /run/current-system/sw/bin/xfce4-session")
    server.succeed("getent passwd klarkc | grep '^klarkc:'")
    server.succeed("test ! -e /home/klarkc/.git")
  '';
}
