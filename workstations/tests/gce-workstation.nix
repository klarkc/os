{ pkgs }:

pkgs.testers.runNixOSTest {
  name = "solo-gce-iap-workstation";
  nodes.server = { ... }: {
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
    server.wait_for_unit("sshd.service")
    server.succeed("id klarkc")
    server.succeed("test -d /home/klarkc")
    server.succeed("test -x /run/current-system/sw/bin/git")
    server.succeed("ss -lnt | grep ':3389'")
    server.succeed("ss -lnt | grep ':22'")

    # The actual NixOS nftables allow rules MUST bind both administrative
    # ports to the IAP TCP forwarding IPv4 source range.
    status, rules = server.execute("nft -nn list chain inet nixos-fw input-allow")
    assert status == 0, f"nftables input-allow is missing: {rules}"
    for port in (22, 3389):
        matching = [line for line in rules.splitlines() if f"tcp dport {port} " in line]
        assert matching, f"missing IAP-only allowance for port {port}: {rules}"
        for line in matching:
            assert "ip saddr 35.235.240.0/20" in line and " accept" in line, (
                f"unexpected unrestricted ingress for {port}: {line}"
            )

    # An IAP tunnel authenticates the transport, NOT the graphical login.
    server.succeed("test -x /run/current-system/sw/bin/solo-xrdp-set-password")
    server.fail("solo-xrdp-set-password")  # no interactive administrator TTY
    server.succeed("getent shadow klarkc | grep '^klarkc:!:'")
    server.succeed("${pkgs.openssh}/bin/sshd -t -f /etc/ssh/sshd_config")
    server.succeed("grep -Eqi '^[[:space:]]*PasswordAuthentication[[:space:]]+no[[:space:]]*$' /etc/ssh/sshd_config")
    server.succeed("grep -Eqi '^[[:space:]]*PermitRootLogin[[:space:]]+prohibit-password[[:space:]]*$' /etc/ssh/sshd_config")

    # Verify Xorg plus a real, installed XFCE fallback when user XMonad
    # session has not yet been installed from the HOME dotfiles checkout.
    server.succeed("test -x ${pkgs.xfce4-session}/bin/xfce4-session")
    server.succeed("grep -F 'xmonad-session' /etc/xrdp/startwm.sh")
    server.succeed("grep -F 'xfce4-session' /etc/xrdp/startwm.sh")

    # The GCE workstation has NO third-party VPN dependency.
    server.succeed("test ! -e /run/current-system/sw/bin/tailscale")
    server.succeed("! systemctl is-active tailscaled.service")
    server.succeed("! ip link show wg0")
    server.succeed("test ! -e /home/klarkc/.git")

    # Restarting the SAME VM must preserve writable /home, including the
    # future direct $HOME Git checkout. Do not mistake a rebuild for reboot.
    server.succeed("install -d -m 0700 -o klarkc -g users /home/klarkc/.local/state")
    server.succeed("printf 'gce-iap-ci-marker\n' > /home/klarkc/.local/state/gce-iap-ci-marker")
    server.succeed("chown klarkc:users /home/klarkc/.local/state/gce-iap-ci-marker")
    server.reboot()
    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("xrdp.service")
    server.wait_for_unit("xrdp-sesman.service")
    server.succeed("grep -Fx 'gce-iap-ci-marker' /home/klarkc/.local/state/gce-iap-ci-marker")
    server.succeed("stat -c '%U' /home/klarkc/.local/state/gce-iap-ci-marker | grep -Fx klarkc")
    server.succeed("ss -lnt | grep ':3389'")
    server.succeed("test ! -e /run/current-system/sw/bin/tailscale")
  '';
}
