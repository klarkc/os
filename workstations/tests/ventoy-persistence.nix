{ pkgs }:
let
  # A real USB mass-storage controller in QEMU, backed by a *temporary* COW
  # overlay of a tiny exFAT volume carrying the same Ventoy label.
  # Never presents a writable copy of any physical /dev disk to a VM.
  usbImage = pkgs.runCommand "solo-ventoy-test-usb.img" {
    nativeBuildInputs = [ pkgs.coreutils pkgs.exfatprogs pkgs.parted ];
  } ''
    # Like real Ventoy media, the *partition* is labelled Ventoy, not the
    # entire USB disk. This exercises the parent-device USB transport check.
    truncate -s 68M "$out"
    truncate -s 64M partition.img
    mkfs.exfat -n Ventoy partition.img
    parted -s "$out" mklabel msdos
    parted -s "$out" unit MiB mkpart primary 1 65
    dd if=partition.img of="$out" bs=1M seek=1 conv=notrunc status=none
  '';
in
pkgs.testers.runNixOSTest {
  name = "solo-ventoy-wifi-state-persistence";
  nodes.client = { lib, ... }: {
    imports = [ ../thin-client.nix ];

    users.users.nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" "video" ];
      initialPassword = "test-only";
    };
    # Ensure tests exercise the explicit NOPASSWD helper allowlist.
    security.sudo.wheelNeedsPassword = true;

    virtualisation.memorySize = 2048;
    virtualisation.graphics = true;
    virtualisation.qemu.options = [
      "-device qemu-xhci,id=solo-usb"
      "-drive if=none,id=solo-ventoy-disk,file=${usbImage},format=raw,snapshot=on"
      "-device usb-storage,drive=solo-ventoy-disk"
    ];
    system.stateVersion = "26.05";
  };

  testScript = ''
    import datetime as dt

    # QEMU defaults to -no-reboot. Keep the SAME process/USB COW overlay
    # running across a real guest reboot, then verify the kernel boot ID.
    client.start(allow_reboot=True)
    client.wait_for_unit("multi-user.target")
    client.wait_for_unit("NetworkManager.service")

    # Assert that the *USB* volume was selected rather than a virtual root disk.
    client.succeed("test -e /dev/disk/by-label/Ventoy")
    client.succeed("test \"$(lsblk -dno TRAN /dev/$(lsblk -no PKNAME $(readlink -f /dev/disk/by-label/Ventoy)))\" = usb")
    client.succeed("mountpoint -q /run/solo-client/ventoy")
    client.succeed("test \"$(findmnt -no FSTYPE /run/solo-client/ventoy)\" = exfat")
    client.succeed("systemctl show -P Result solo-ventoy-state.service | grep -Fx success")

    # Mimic one user-entered Wi-Fi profile, NOT a real secret. It must survive
    # reboot of the guest with an actual (emulated) USB disk.
    client.succeed("printf '%s\\n' '[connection]' 'id=solo-ci-wifi' 'uuid=11111111-2222-3333-4444-555555555555' 'type=wifi' 'autoconnect=true' '[wifi]' 'mode=infrastructure' 'ssid=CI-TEST-NO-SECRETS' '[wifi-security]' 'key-mgmt=wpa-psk' 'psk=ci-test-password' '[ipv4]' 'method=auto' '[ipv6]' 'method=auto' > /etc/NetworkManager/system-connections/solo-ci.nmconnection")
    client.succeed("chmod 600 /etc/NetworkManager/system-connections/solo-ci.nmconnection")
    client.succeed("solo-client-state save")
    # The live-image user must be able to persist state without a password.
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/solo-client-state save")
    client.succeed("grep -Fx 'psk=ci-test-password' /run/solo-client/ventoy/solo-client/wifi/solo-ci.nmconnection")

    # gcloud auth login (NOT application-default login) uses the CLI SQLite
    # database and config_default. No real Google account or secret in CI.
    client.succeed("install -d -m 700 -o nixos -g users /home/nixos/.config /home/nixos/.config/solo-gcloud /home/nixos/.config/solo-gcloud/configurations")
    client.succeed("runuser -u nixos -- sqlite3 /home/nixos/.config/solo-gcloud/credentials.db 'CREATE TABLE ci_fixture (token TEXT NOT NULL)'")
    client.succeed("runuser -u nixos -- sqlite3 /home/nixos/.config/solo-gcloud/credentials.db \"INSERT INTO ci_fixture VALUES ('ci-synthetic-only')\"")
    client.succeed("printf '%s\\n' '[core]' 'account = ci@example.invalid' > /home/nixos/.config/solo-gcloud/configurations/config_default")
    client.succeed("chown nixos:users /home/nixos/.config/solo-gcloud/configurations/config_default")
    client.succeed("chmod 600 /home/nixos/.config/solo-gcloud/configurations/config_default")
    client.succeed("runuser -u nixos -- /run/current-system/sw/bin/solo-gce-iap has-credentials")

    # Only the exact save command has passwordless sudo. In particular the
    # unprivileged user cannot call the boot-time root restore helper.
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/solo-client-state save")
    client.succeed("runuser -u nixos -- sh -c '! sudo -n /run/current-system/sw/bin/solo-client-state restore'")
    client.succeed("sqlite3 /run/solo-client/ventoy/solo-client/gcloud-cli/credentials.db 'SELECT token FROM ci_fixture' | grep -Fx ci-synthetic-only")
    client.succeed("grep -Fx 'account = ci@example.invalid' /run/solo-client/ventoy/solo-client/gcloud-cli/config_default")
    client.succeed("! test -e /run/solo-client/ventoy/solo-client/gcloud-cli/access_tokens.db")
    client.succeed("! test -e /run/solo-client/ventoy/solo-client/gcloud-cli/logs")
    client.succeed("! test -e /run/solo-client/ventoy/solo-client/google-adc.json")
    client.succeed("! test -e /run/solo-client/ventoy/solo-client/wireguard")
    # exFAT represents regular files with 0700 under umask=077: unlike
    # POSIX home state, chmod 0600 is not a per-file property on exFAT.
    # Assert only root can access the USB credential (no group/other bits).
    client.succeed("test -z \"$(find /run/solo-client/ventoy/solo-client/gcloud-cli/credentials.db -perm /077 -print)\"")
    client.succeed("test \"$(stat -c %U /run/solo-client/ventoy/solo-client/gcloud-cli/credentials.db)\" = root")

    # Offline fake gcloud validates IAP CLI arguments; it never logs in,
    # contacts Google or uses a public endpoint. The real IAP is BuildGCE E2E.
    client.succeed("printf '%s\\n' '#!/bin/sh' 'printf \"%s\\\\n\" \"$@\" > /tmp/ci-iap-argv' 'echo \"Listening on port [13389].\"' > /tmp/ci-mock-gcloud")
    client.succeed("chmod 755 /tmp/ci-mock-gcloud")
    client.succeed("runuser -u nixos -- env SOLO_GCLOUD_BIN=/tmp/ci-mock-gcloud /run/current-system/sw/bin/solo-gce-iap tunnel | grep -Fx 'Listening on port [13389].'")
    client.succeed("grep -Fx 'start-iap-tunnel' /tmp/ci-iap-argv")
    client.succeed("grep -Fx 'solo-workstation' /tmp/ci-iap-argv")
    client.succeed("grep -Fx -- '--zone=southamerica-east1-b' /tmp/ci-iap-argv")
    client.succeed("grep -Fx -- '--project=argon-surf-472319-b0' /tmp/ci-iap-argv")
    client.succeed("grep -Fx -- '--local-host-port=127.0.0.1:13389' /tmp/ci-iap-argv")
    client.succeed("grep -Fx '3389' /tmp/ci-iap-argv")
    client.succeed("! grep -E 'natIP|WireGuard|51820|gce-endpoint' /tmp/ci-iap-argv")

    # Simulate removal of volatile RAM state while the USB overlay persists.
    client.succeed("rm /home/nixos/.config/solo-gcloud/credentials.db")
    client.succeed("rm /home/nixos/.config/solo-gcloud/configurations/config_default")
    client.succeed("rm /etc/NetworkManager/system-connections/solo-ci.nmconnection")

    first_boot_id = client.succeed("cat /proc/sys/kernel/random/boot_id").strip()
    # Ctrl+Alt+Delete from the test driver can be intercepted by the running
    # graphical session. Schedule a real systemd reboot instead, so a command
    # return is not confused with a reboot (or a lost test-driver backdoor).
    client.succeed("systemd-run --on-active=2s --unit=solo-ci-reboot -- systemctl reboot")
    client.connected = False
    client.wait_for_qmp_event(
      lambda event: event.get("event") == "RESET",
      timeout=dt.timedelta(minutes=3),
    )
    client.wait_for_unit("multi-user.target")
    second_boot_id = client.succeed("cat /proc/sys/kernel/random/boot_id").strip()
    assert first_boot_id and second_boot_id and first_boot_id != second_boot_id, "QEMU guest did not reboot"
    print(f"Guest reboot verified: {first_boot_id} -> {second_boot_id}")
    client.wait_for_unit("NetworkManager.service")

    # The USB COW overlay persists across guest reboot in the SAME QEMU VM.
    client.succeed("mountpoint -q /run/solo-client/ventoy")
    client.succeed("grep -Fx 'psk=ci-test-password' /etc/NetworkManager/system-connections/solo-ci.nmconnection")
    client.succeed("nmcli -t -f NAME con show | grep -Fx 'solo-ci-wifi'")
    client.succeed("sqlite3 /home/nixos/.config/solo-gcloud/credentials.db 'SELECT token FROM ci_fixture' | grep -Fx ci-synthetic-only")
    client.succeed("grep -Fx 'account = ci@example.invalid' /home/nixos/.config/solo-gcloud/configurations/config_default")
    client.succeed("runuser -u nixos -- /run/current-system/sw/bin/solo-gce-iap has-credentials")
    client.succeed("test \"$(stat -c %a /home/nixos/.config/solo-gcloud/credentials.db)\" = 600")
    client.succeed("test \"$(stat -c %U /home/nixos/.config/solo-gcloud/credentials.db)\" = nixos")
    client.succeed("test \"$(stat -c %a /home/nixos/.config/solo-gcloud/configurations/config_default)\" = 600")
    client.succeed("! test -e /home/nixos/.config/gcloud/application_default_credentials.json")
    client.succeed("test \"$(stat -c %a /etc/NetworkManager/system-connections/solo-ci.nmconnection)\" = 600")
  '';
}
