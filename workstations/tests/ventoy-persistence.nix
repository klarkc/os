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
    client.succeed("solo-client-state set-host solo-ci-server")
    client.succeed("solo-client-state save")
    # The live-image user must be able to persist state without a password.
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/solo-client-state save")
    client.succeed("grep -Fx 'psk=ci-test-password' /run/solo-client/ventoy/solo-client/wifi/solo-ci.nmconnection")
    client.succeed("test \"$(solo-client-state get-host)\" = solo-ci-server")

    # A harmless fixture in place of a real Google OAuth refresh token.
    # The whole Google config directory is NOT saved to the Ventoy drive.
    client.succeed("install -d -m 700 -o nixos -g users /home/nixos/.config/gcloud")
    client.succeed("printf '%s\n' '{\"type\":\"authorized_user\",\"client_id\":\"ci-synthetic-only\"}' > /home/nixos/.config/gcloud/application_default_credentials.json")
    client.succeed("chown nixos:users /home/nixos/.config/gcloud/application_default_credentials.json")
    client.succeed("chmod 600 /home/nixos/.config/gcloud/application_default_credentials.json")
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/solo-client-state save")
    client.succeed("grep -F 'ci-synthetic-only' /run/solo-client/ventoy/solo-client/google-adc.json")
    client.succeed("! test -e /run/solo-client/ventoy/solo-client/credentials.db")

    # The WireGuard private key is generated ONCE, exclusively on the USB.
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/solo-client-state init-wg")
    client.succeed("test -s /run/solo-client/ventoy/solo-client/wireguard/client.key")
    first_wg_public = client.succeed("sudo -n /run/current-system/sw/bin/solo-client-state wg-public").strip()
    assert len(first_wg_public) == 44

    # Validate offline GCE API response parsing before any real Google login.
    client.succeed("printf '{\"status\":\"RUNNING\",\"networkInterfaces\":[{\"accessConfigs\":[{\"natIP\":\"203.0.113.17\"}]}],\"metadata\":{\"items\":[{\"key\":\"solo-wg-server-public-key\",\"value\":\"%s\"}]}}' \"$(sudo -n /run/current-system/sw/bin/solo-client-state wg-public)\" | runuser -u nixos -- /run/current-system/sw/bin/solo-gce-endpoint parse | cut -f1 | grep -Fx 203.0.113.17")
    client.succeed("! printf '{\"status\":\"TERMINATED\"}' | /run/current-system/sw/bin/solo-gce-endpoint parse")
    client.succeed("! printf '{\"status\":\"RUNNING\",\"networkInterfaces\":[{\"accessConfigs\":[{\"natIP\":\"999.999.999.999\"}]}]}' | /run/current-system/sw/bin/solo-gce-endpoint parse")

    # The helper accepts a peer public key but installs only a private route,
    # never a default route or an externally reachable RDP listener.
    peer_public = client.succeed("wg genkey | wg pubkey").strip()
    client.succeed(f"runuser -u nixos -- sudo -n /run/current-system/sw/bin/solo-client-wg connect 203.0.113.17 {peer_public}")
    client.succeed("ip -4 route get 10.77.0.1 | grep -F solo-wg")
    client.succeed("wg show solo-wg endpoints | grep -F '203.0.113.17:51820'")
    client.succeed("! ip -4 route show default | grep -F solo-wg")

    # Simulate RAM being discarded at power-off; keep the USB overlay intact.
    client.succeed("rm /home/nixos/.config/gcloud/application_default_credentials.json")

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
    client.succeed("test \"$(solo-client-state get-host)\" = solo-ci-server")
    client.succeed("nmcli -t -f NAME con show | grep -Fx 'solo-ci-wifi'")
    client.succeed("grep -F 'ci-synthetic-only' /home/nixos/.config/gcloud/application_default_credentials.json")
    client.succeed("test \"$(stat -c %a /home/nixos/.config/gcloud/application_default_credentials.json)\" = 600")
    client.succeed("test \"$(stat -c %U /home/nixos/.config/gcloud/application_default_credentials.json)\" = nixos")
    second_wg_public = client.succeed("sudo -n /run/current-system/sw/bin/solo-client-state wg-public").strip()
    assert second_wg_public == first_wg_public, "USB WireGuard private key rotated after reboot"
    client.succeed("test \"$(stat -c %a /etc/NetworkManager/system-connections/solo-ci.nmconnection)\" = 600")
  '';
}
