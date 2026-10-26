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
    status, effective_ssh = server.execute("${pkgs.openssh}/bin/sshd -T -f /etc/ssh/sshd_config 2>&1")
    print("sshd effective policy:", [line for line in effective_ssh.splitlines() if line.startswith(("passwordauthentication ", "permitrootlogin "))])
    assert status == 0, f"sshd -T could not inspect generated configuration: {effective_ssh}"
    assert "passwordauthentication no" in effective_ssh.splitlines(), "SSH password authentication must be disabled"
    assert "permitrootlogin prohibit-password" in effective_ssh.splitlines(), "Root SSH must require key authentication"
    server.succeed("test -e /run/current-system/sw/bin/tailscale")
    server.succeed("test -e /run/current-system/sw/bin/xfce4-session")
    server.succeed("getent passwd klarkc | grep '^klarkc:'")
    server.succeed("test ! -e /home/klarkc/.git")
  '';
}
