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
    server.succeed("sshd -T | grep -Fx 'passwordauthentication no'")
    server.succeed("sshd -T | grep -Fx 'permitrootlogin prohibit-password'")
    server.succeed("iptables -S INPUT | grep -E 'DROP|REJECT'")
    server.succeed("test -e /run/current-system/sw/bin/tailscale")
    server.succeed("test -e /run/current-system/sw/bin/xfce4-session")
    server.succeed("getent passwd klarkc | grep '^klarkc:'")
    server.succeed("test ! -e /home/klarkc/.git")
  '';
}
