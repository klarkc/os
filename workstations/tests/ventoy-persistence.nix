{ pkgs }:
let
  # A real USB mass-storage controller in QEMU, backed by a *temporary* COW
  # overlay of Ventoy's two-partition data + VTOYEFI layout.
  # Never presents a writable copy of any physical /dev disk to a VM.
  usbImage = pkgs.runCommand "lpklarkc-ventoy-test-usb.img" {
    nativeBuildInputs = [ pkgs.coreutils pkgs.exfatprogs pkgs.parted pkgs.dosfstools ];
  } ''
    # Like real Ventoy media, the *partition* is labelled Ventoy, not the
    # entire USB disk. This exercises the parent-device USB transport check.
    truncate -s 100M "$out"
    truncate -s 64M partition.img
    truncate -s 32M efi.img
    mkfs.exfat -n Ventoy partition.img
    mkfs.vfat -F 32 -n VTOYEFI efi.img
    parted -s "$out" mklabel msdos
    parted -s "$out" unit MiB mkpart primary 1 65
    parted -s "$out" unit MiB mkpart primary 65 97
    dd if=partition.img of="$out" bs=1M seek=1 conv=notrunc status=none
    dd if=efi.img of="$out" bs=1M seek=65 conv=notrunc status=none
  '';
in
pkgs.testers.runNixOSTest {
  name = "lpklarkc-ventoy-wifi-state-persistence";
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
      "-device qemu-xhci,id=lpklarkc-usb"
      "-drive if=none,id=lpklarkc-ventoy-disk,file=${usbImage},format=raw,snapshot=on"
      "-device usb-storage,drive=lpklarkc-ventoy-disk"
    ];
    # Only the VM includes tools for simulated Ventoy partition relabel/dm.
    environment.systemPackages = [ pkgs.exfatprogs pkgs.lvm2 ];
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
    client.succeed("mountpoint -q /run/lpklarkc/ventoy")
    client.succeed("test \"$(findmnt -no FSTYPE /run/lpklarkc/ventoy)\" = exfat")
    # nm-online may time out after manually activating a valid Wi-Fi link.
    # Test the fallback while NetworkManager and its default route are up.
    client.succeed("printf '%s\\n' '#!/bin/sh' 'echo wifi:connected' > /tmp/ci-mock-nmcli")
    client.succeed("printf '%s\\n' '#!/bin/sh' 'echo \"default via 192.0.2.1 dev wlan0\"' > /tmp/ci-mock-ip")
    client.succeed("chmod 755 /tmp/ci-mock-nmcli /tmp/ci-mock-ip")
    client.succeed("runuser -u nixos -- env LPKLARKC_NM_ONLINE_BIN=/bin/false LPKLARKC_NMCLI_BIN=/tmp/ci-mock-nmcli LPKLARKC_IP_BIN=/tmp/ci-mock-ip /run/current-system/sw/bin/lpklarkc --check-network")
    client.succeed("! runuser -u nixos -- env LPKLARKC_NM_ONLINE_BIN=/bin/false LPKLARKC_NMCLI_BIN=/bin/false LPKLARKC_IP_BIN=/tmp/ci-mock-ip /run/current-system/sw/bin/lpklarkc --check-network")
    client.succeed("systemctl show -P Result lpklarkc-ventoy-state.service | grep -Fx success")
    # REGRESSION: photo from the real Dell (2026-10-27) showed an ISO
    # booted from Ventoy but state missing. A later USB mount must recover,
    # without rebooting and without broad sudo privileges.
    # Baseline (old build) fails: "ensure" is not implemented, and the
    # kiosk never retries after the one boot-time restore attempt.
    client.succeed("umount /run/lpklarkc/ventoy")
    client.succeed("! mountpoint -q /run/lpklarkc/ventoy")
    client.succeed("lpklarkc-state ensure")
    client.succeed("mountpoint -q /run/lpklarkc/ventoy")
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/lpklarkc-state ensure")


    # Mimic one user-entered Wi-Fi profile, NOT a real secret. It must survive
    # reboot of the guest with an actual (emulated) USB disk.
    client.succeed("printf '%s\\n' '[connection]' 'id=lpklarkc-ci-wifi' 'uuid=11111111-2222-3333-4444-555555555555' 'type=wifi' 'autoconnect=true' '[wifi]' 'mode=infrastructure' 'ssid=CI-TEST-NO-SECRETS' '[wifi-security]' 'key-mgmt=wpa-psk' 'psk=ci-test-password' '[ipv4]' 'method=auto' '[ipv6]' 'method=auto' > /etc/NetworkManager/system-connections/lpklarkc-ci.nmconnection")
    client.succeed("chmod 600 /etc/NetworkManager/system-connections/lpklarkc-ci.nmconnection")
    client.succeed("lpklarkc-state save")
    # The live-image user must be able to persist state without a password.
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/lpklarkc-state save")
    client.succeed("grep -Fx 'psk=ci-test-password' /run/lpklarkc/ventoy/lpklarkc/wifi/lpklarkc-ci.nmconnection")

    # gcloud auth login (NOT application-default login) uses the CLI SQLite
    # database and config_default. No real Google account or secret in CI.
    client.succeed("install -d -m 700 -o nixos -g users /home/nixos/.config /home/nixos/.config/lpklarkc-gcloud /home/nixos/.config/lpklarkc-gcloud/configurations")
    client.succeed("runuser -u nixos -- sqlite3 /home/nixos/.config/lpklarkc-gcloud/credentials.db 'CREATE TABLE ci_fixture (token TEXT NOT NULL)'")
    client.succeed("runuser -u nixos -- sqlite3 /home/nixos/.config/lpklarkc-gcloud/credentials.db \"INSERT INTO ci_fixture VALUES ('ci-synthetic-only')\"")
    client.succeed("printf '%s\\n' '[core]' 'account = ci@example.invalid' > /home/nixos/.config/lpklarkc-gcloud/configurations/config_default")
    client.succeed("chown nixos:users /home/nixos/.config/lpklarkc-gcloud/configurations/config_default")
    client.succeed("chmod 600 /home/nixos/.config/lpklarkc-gcloud/configurations/config_default")
    client.succeed("runuser -u nixos -- /run/current-system/sw/bin/lpklarkc-iap has-credentials")

    # A TLS pin must survive power loss so FreeRDP /cert:tofu does not
    # silently accept a different XRDP server certificate next boot.
    client.succeed("install -d -m 700 -o nixos -g users /home/nixos/.config/freerdp /home/nixos/.config/freerdp/server")
    client.succeed("printf '%s\\n' 'ci-xrdp-certificate' > /home/nixos/.config/freerdp/server/127.0.0.1_13389.pem")
    client.succeed("chown nixos:users /home/nixos/.config/freerdp/server/127.0.0.1_13389.pem")
    client.succeed("chmod 600 /home/nixos/.config/freerdp/server/127.0.0.1_13389.pem")

    # Only the exact save command has passwordless sudo. In particular the
    # unprivileged user cannot call the boot-time root restore helper.
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/lpklarkc-state save")
    client.succeed("runuser -u nixos -- sh -c '! sudo -n /run/current-system/sw/bin/lpklarkc-state restore'")
    client.succeed("sqlite3 /run/lpklarkc/ventoy/lpklarkc/gcloud-cli/credentials.db 'SELECT token FROM ci_fixture' | grep -Fx ci-synthetic-only")
    client.succeed("grep -Fx 'account = ci@example.invalid' /run/lpklarkc/ventoy/lpklarkc/gcloud-cli/config_default")
    client.succeed("grep -Fx 'ci-xrdp-certificate' /run/lpklarkc/ventoy/lpklarkc/freerdp/server/127.0.0.1_13389.pem")
    client.succeed("! test -e /run/lpklarkc/ventoy/lpklarkc/gcloud-cli/access_tokens.db")
    client.succeed("! test -e /run/lpklarkc/ventoy/lpklarkc/gcloud-cli/logs")
    client.succeed("! test -e /run/lpklarkc/ventoy/lpklarkc/google-adc.json")
    client.succeed("! test -e /run/lpklarkc/ventoy/lpklarkc/wireguard")
    # exFAT represents regular files with 0700 under umask=077: unlike
    # POSIX home state, chmod 0600 is not a per-file property on exFAT.
    # Assert only root can access the USB credential (no group/other bits).
    client.succeed("test -z \"$(find /run/lpklarkc/ventoy/lpklarkc/gcloud-cli/credentials.db -perm /077 -print)\"")
    client.succeed("test \"$(stat -c %U /run/lpklarkc/ventoy/lpklarkc/gcloud-cli/credentials.db)\" = root")

    # Offline fake gcloud validates IAP CLI arguments; it never logs in,
    # contacts Google or uses a public endpoint. The real IAP is BuildGCE E2E.
    client.succeed("printf '%s\\n' '#!/bin/sh' 'printf \"%s\\\\n\" \"$@\" > /tmp/ci-iap-argv' 'echo \"Listening on port [13389].\"' > /tmp/ci-mock-gcloud")
    client.succeed("chmod 755 /tmp/ci-mock-gcloud")
    client.succeed("runuser -u nixos -- env LPKLARKC_GCLOUD_BIN=/tmp/ci-mock-gcloud /run/current-system/sw/bin/lpklarkc-iap tunnel | grep -Fx 'Listening on port [13389].'")
    client.succeed("grep -Fx 'start-iap-tunnel' /tmp/ci-iap-argv")
    client.succeed("grep -Fx 'wsklarkc' /tmp/ci-iap-argv")
    client.succeed("grep -Fx -- '--zone=southamerica-east1-b' /tmp/ci-iap-argv")
    client.succeed("grep -Fx -- '--project=argon-surf-472319-b0' /tmp/ci-iap-argv")
    client.succeed("grep -Fx -- '--local-host-port=127.0.0.1:13389' /tmp/ci-iap-argv")
    client.succeed("grep -Fx '3389' /tmp/ci-iap-argv")
    client.succeed("! grep -E 'natIP|WireGuard|51820|gce-endpoint' /tmp/ci-iap-argv")

    # Reproduce Ventoy installations whose data partition was relabelled.
    # VTOYEFI is still on the same USB disk and the helper must find part 1.
    client.succeed("umount /run/lpklarkc/ventoy")
    client.succeed("exfatlabel \"$(readlink -f /dev/disk/by-label/Ventoy)\" LPKDATA")
    client.succeed("udevadm trigger --subsystem-match=block --action=change")
    client.succeed("udevadm settle")
    client.succeed("test -e /dev/disk/by-label/VTOYEFI")
    client.succeed("! test -e /dev/disk/by-label/Ventoy")
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/lpklarkc-state ensure")
    client.succeed("mountpoint -q /run/lpklarkc/ventoy")

    # Ventoy 1.1.18 may expose the data partition through a device mapper
    # when the raw ISO-containing partition is busy. Simulate its DM path.
    client.succeed("umount /run/lpklarkc/ventoy")
    client.succeed("modprobe dm_mod")
    client.succeed("usb_data=$(readlink -f /dev/disk/by-label/LPKDATA); printf '0 %s linear %s 0\\n' \"$(blockdev --getsz \"$usb_data\")\" \"$usb_data\" | dmsetup create VentoyPart")
    client.succeed("test -b /dev/mapper/VentoyPart")
    client.succeed("lpklarkc-state ensure")
    client.succeed("mountpoint -q /run/lpklarkc/ventoy")
    client.succeed("umount /run/lpklarkc/ventoy")
    client.succeed("dmsetup remove VentoyPart")
    client.succeed("lpklarkc-state ensure")
    client.succeed("mountpoint -q /run/lpklarkc/ventoy")

    # Dell regression (2026-10-28): Ventoy bootable, direct raw USB
    # mount returns EBUSY; older Ventoy used /dev/mapper/sdX1.
    # Use the older sdX1 mapper *shape*, but a distinct synthetic name;
    # aliasing the real /dev/sda1 name causes a nondeterministic udev EBUSY.
    # Mock mount only in CI via bash exported function, not in production.
    client.succeed("umount /run/lpklarkc/ventoy")
    client.succeed("usb_data=$(readlink -f /dev/disk/by-label/LPKDATA); legacy=sdz1; test \"$legacy\" != \"$(basename \"$usb_data\")\"; printf '%s\\n' \"$legacy\" > /tmp/ci-legacy-device-name; printf '0 %s linear %s 0\\n' \"$(blockdev --getsz \"$usb_data\")\" \"$usb_data\" | dmsetup create \"$legacy\"")
    client.succeed("test -b /dev/mapper/$(cat /tmp/ci-legacy-device-name)")
    client.succeed("""bash -c 'mount() {
      for arg in "$@"; do
        case "$arg" in
          /dev/disk/by-label/LPKDATA|/dev/sd?1) return 32 ;;
        esac
      done
      command mount "$@"
    }; export -f mount; lpklarkc-state ensure'""")
    client.succeed("findmnt -no SOURCE /run/lpklarkc/ventoy | grep -E '/dev/(mapper/|dm-)'")
    client.succeed("umount /run/lpklarkc/ventoy")
    # udev/blkid may transiently hold the synthetic mapper open even after
    # the test unmounts it; --retry is purpose-built for this EBUSY race.
    client.succeed("udevadm settle && dmsetup remove --retry \"$(cat /tmp/ci-legacy-device-name)\"")
    client.succeed("! test -e /dev/mapper/$(cat /tmp/ci-legacy-device-name)")
    client.succeed("udevadm trigger --subsystem-match=block --action=change && udevadm settle")

    # Older Ventoy may expose no alias at all. Ensure must create a
    # USB-validated linear mapping, without touching the internal HDD.
    client.succeed("""bash -c 'mount() {
      for arg in "$@"; do
        case "$arg" in
          /dev/disk/by-label/LPKDATA|/dev/sd?1) return 32 ;;
        esac
      done
      command mount "$@"
    }; export -f mount; lpklarkc-state ensure'""")
    client.succeed("findmnt -no SOURCE /run/lpklarkc/ventoy | grep -E '/dev/(mapper/|dm-)'")
    client.succeed("grep -Fx 'psk=ci-test-password' /run/lpklarkc/ventoy/lpklarkc/wifi/lpklarkc-ci.nmconnection")

    # REGRESSION: If boot-time USB mounting fails, the kiosk later calls
    # 'ensure'. That action must restore the previous Google CLI identity,
    # Wi-Fi profile and TLS certificate, not merely mount the USB.
    client.succeed("umount /run/lpklarkc/ventoy")
    client.succeed("rm /home/nixos/.config/lpklarkc-gcloud/credentials.db")
    client.succeed("rm /home/nixos/.config/lpklarkc-gcloud/configurations/config_default")
    client.succeed("rm /home/nixos/.config/freerdp/server/127.0.0.1_13389.pem")
    client.succeed("rm /etc/NetworkManager/system-connections/lpklarkc-ci.nmconnection")
    client.succeed("runuser -u nixos -- sudo -n /run/current-system/sw/bin/lpklarkc-state ensure")
    client.succeed("sqlite3 /home/nixos/.config/lpklarkc-gcloud/credentials.db 'SELECT token FROM ci_fixture' | grep -Fx ci-synthetic-only")
    client.succeed("grep -Fx 'psk=ci-test-password' /etc/NetworkManager/system-connections/lpklarkc-ci.nmconnection")
    client.succeed("nmcli -t -f NAME con show | grep -Fx lpklarkc-ci-wifi")
    client.succeed("grep -Fx 'ci-xrdp-certificate' /home/nixos/.config/freerdp/server/127.0.0.1_13389.pem")

    # Security regression: a wrong filesystem mounted at the persistence
    # path must not be accepted for storing Google OAuth credentials.
    client.succeed("umount /run/lpklarkc/ventoy")
    client.succeed("mount -t tmpfs -o size=8M tmpfs /run/lpklarkc/ventoy")
    client.succeed("! lpklarkc-state is-ready")
    client.succeed("! lpklarkc-state save")
    client.succeed("umount /run/lpklarkc/ventoy")
    client.succeed("lpklarkc-state ensure")
    client.succeed("mountpoint -q /run/lpklarkc/ventoy")

    # Simulate removal of volatile RAM state while the USB overlay persists.
    client.succeed("rm /home/nixos/.config/lpklarkc-gcloud/credentials.db")
    client.succeed("rm /home/nixos/.config/lpklarkc-gcloud/configurations/config_default")
    client.succeed("rm /home/nixos/.config/freerdp/server/127.0.0.1_13389.pem")
    client.succeed("rm /etc/NetworkManager/system-connections/lpklarkc-ci.nmconnection")

    first_boot_id = client.succeed("cat /proc/sys/kernel/random/boot_id").strip()
    # Ctrl+Alt+Delete from the test driver can be intercepted by the running
    # graphical session. Schedule a real systemd reboot instead, so a command
    # return is not confused with a reboot (or a lost test-driver backdoor).
    client.succeed("systemd-run --on-active=2s --unit=lpklarkc-ci-reboot -- systemctl reboot")
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
    client.succeed("mountpoint -q /run/lpklarkc/ventoy")
    client.succeed("grep -Fx 'psk=ci-test-password' /etc/NetworkManager/system-connections/lpklarkc-ci.nmconnection")
    client.succeed("nmcli -t -f NAME con show | grep -Fx 'lpklarkc-ci-wifi'")
    client.succeed("sqlite3 /home/nixos/.config/lpklarkc-gcloud/credentials.db 'SELECT token FROM ci_fixture' | grep -Fx ci-synthetic-only")
    client.succeed("grep -Fx 'account = ci@example.invalid' /home/nixos/.config/lpklarkc-gcloud/configurations/config_default")
    client.succeed("grep -Fx 'ci-xrdp-certificate' /home/nixos/.config/freerdp/server/127.0.0.1_13389.pem")
    client.succeed("test \"$(stat -c %U /home/nixos/.config/freerdp/server/127.0.0.1_13389.pem)\" = nixos")
    client.succeed("runuser -u nixos -- /run/current-system/sw/bin/lpklarkc-iap has-credentials")
    client.succeed("test \"$(stat -c %a /home/nixos/.config/lpklarkc-gcloud/credentials.db)\" = 600")
    client.succeed("test \"$(stat -c %U /home/nixos/.config/lpklarkc-gcloud/credentials.db)\" = nixos")
    client.succeed("test \"$(stat -c %a /home/nixos/.config/lpklarkc-gcloud/configurations/config_default)\" = 600")
    client.succeed("! test -e /home/nixos/.config/gcloud/application_default_credentials.json")
    client.succeed("test \"$(stat -c %a /etc/NetworkManager/system-connections/lpklarkc-ci.nmconnection)\" = 600")
  '';
}
