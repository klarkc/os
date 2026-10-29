{ pkgs, determinateModule }:

pkgs.testers.runNixOSTest {
  name = "wsklarkc-gce-iap-workstation";
  nodes.server = { ... }: {
    imports = [ determinateModule ../gcp-workstation.nix ];
    virtualisation.memorySize = 3072;
    virtualisation.graphics = true;
    system.stateVersion = "26.05";
  };

  testScript = ''
    # QEMU's default -no-reboot option makes a guest reboot terminate the VM.
    # Keep this SAME QEMU process and its writable disk across the restart.
    server.start(allow_reboot=True)
    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("xrdp.service")
    server.wait_for_unit("xrdp-sesman.service")
    server.wait_for_unit("sshd.service")
    server.succeed("hostname | grep -Fx wsklarkc")
    server.succeed("id klarkc")
    server.succeed("test -d /home/klarkc")
    server.succeed("test -x /run/current-system/sw/bin/git")
    server.succeed("systemctl cat nix-daemon.service | grep -F determinate-nixd")
    server.succeed("test -r /etc/determinate/config.json")
    server.succeed("grep -F disabled /etc/determinate/config.json")
    server.succeed("systemctl is-enabled nix-gc.timer | grep -Fx enabled")
    server.succeed("systemctl cat nix-gc.service | grep -F -- '--delete-older-than 30d'")
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
    server.succeed("test -x /run/current-system/sw/bin/wsklarkc-xrdp-set-password")
    server.fail("wsklarkc-xrdp-set-password")  # no interactive administrator TTY
    server.succeed("getent shadow klarkc | grep '^klarkc:!:'")
    server.succeed("${pkgs.openssh}/bin/sshd -t -f /etc/ssh/sshd_config")
    server.succeed("grep -Eqi '^[[:space:]]*PasswordAuthentication[[:space:]]+no[[:space:]]*$' /etc/ssh/sshd_config")
    server.succeed("grep -Eqi '^[[:space:]]*PermitRootLogin[[:space:]]+prohibit-password[[:space:]]*$' /etc/ssh/sshd_config")

    # XMonad must be usable in the pre-dotfiles bootstrap state.
    # Fail if any XFCE session or Lemurs launcher was installed.
    server.succeed("test -x /run/current-system/sw/bin/xmonad")
    server.succeed("test -x /run/current-system/sw/bin/xterm")
    server.succeed("grep -F 'wsklarkc-xrdp-session' /etc/xrdp/startwm.sh")
    # A preserved GCE RAM image is useless if sesman has destroyed XMonad.
    # These are necessary configuration checks, not reconnection E2E proof.
    for setting in ("KillDisconnected=false", "DisconnectedTimeLimit=0",
                    "IdleTimeLimit=0", "Policy=Default"):
        server.succeed("grep -Fx " + setting + " /etc/xrdp/sesman.ini")
    server.succeed("test -x /run/current-system/sw/bin/wsklarkc-xrdp-session")
    server.succeed("grep -F 'XRDP_PULSE_SOURCE_SOCKET' /run/current-system/sw/bin/wsklarkc-xrdp-session")
    server.succeed("grep -F 'xrdp-sink' /run/current-system/sw/bin/wsklarkc-xrdp-session")
    server.succeed("grep -F 'xrdp-source' /run/current-system/sw/bin/wsklarkc-xrdp-session")
    server.succeed("test -f /run/current-system/sw/lib/pipewire-0.3/libpipewire-module-xrdp.so")
    server.succeed("test -x /run/current-system/sw/bin/pw-cli")
    server.succeed("test -x /run/current-system/sw/bin/pactl")
    server.succeed("systemctl --user -M klarkc@ status pipewire.service >/dev/null 2>&1 || true")
    server.succeed("test -e /etc/systemd/user/pipewire.service || test -e /run/current-system/sw/lib/systemd/user/pipewire.service")
    server.succeed("test -e /etc/systemd/user/pipewire-pulse.service || test -e /run/current-system/sw/lib/systemd/user/pipewire-pulse.service")
    server.succeed("test -e /etc/systemd/user/wireplumber.service || test -e /run/current-system/sw/lib/systemd/user/wireplumber.service")
    server.fail("grep -Eiq 'xfce|startxfce' /etc/xrdp/startwm.sh")
    server.succeed("test ! -e /run/current-system/sw/bin/xfce4-session")
    server.succeed("test ! -e /run/current-system/sw/bin/lemurs")

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
    old_boot_id = server.succeed("cat /proc/sys/kernel/random/boot_id").strip()
    # Unlike QEMU's Ctrl+Alt+Delete key, systemd reboot cannot be intercepted
    # by a graphical display manager. Schedule it so the test-driver root shell
    # can return cleanly before systemd tears down the guest.
    server.succeed("systemd-run --unit=ci-graceful-reboot --on-active=2s /run/current-system/sw/bin/systemctl reboot")
    server.connected = False
    server.wait_for_unit("multi-user.target")
    assert server.succeed("cat /proc/sys/kernel/random/boot_id").strip() != old_boot_id, (
        "QEMU did not perform a real guest reboot"
    )
    server.wait_for_unit("xrdp.service")
    server.wait_for_unit("xrdp-sesman.service")
    server.succeed("grep -Fx 'gce-iap-ci-marker' /home/klarkc/.local/state/gce-iap-ci-marker")
    server.succeed("stat -c '%U' /home/klarkc/.local/state/gce-iap-ci-marker | grep -Fx klarkc")
    server.succeed("ss -lnt | grep ':3389'")
    server.succeed("test ! -e /run/current-system/sw/bin/tailscale")
  '';
}
