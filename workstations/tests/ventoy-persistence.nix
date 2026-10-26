{ pkgs }:
let
  # A real USB mass-storage controller in QEMU, backed by a *temporary* COW
  # overlay of a tiny exFAT volume carrying the same Ventoy label.
  # Never presents a writable copy of any physical /dev disk to a VM.
  usbImage = pkgs.runCommand "solo-ventoy-test-usb.img" {
    nativeBuildInputs = [ pkgs.coreutils pkgs.exfatprogs ];
  } ''
    truncate -s 64M "$out"
    mkfs.exfat -n Ventoy "$out"
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
    security.sudo.wheelNeedsPassword = false;

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
    start_all()
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
    client.succeed("grep -Fx 'psk=ci-test-password' /run/solo-client/ventoy/solo-client/wifi/solo-ci.nmconnection")
    client.succeed("test \"$(solo-client-state get-host)\" = solo-ci-server")

    # Verify state restore for Tailscale without contacting the coordination
    # service or requiring a real authentication token.
    client.succeed("systemctl stop tailscaled.service")
    client.succeed("printf 'ci-synthetic-tailscale-state\\n' > /var/lib/tailscale/tailscaled.state")
    client.succeed("solo-client-state save")
    client.succeed("rm /var/lib/tailscale/tailscaled.state")
    client.succeed("solo-client-state restore")
    client.succeed("grep -Fx 'ci-synthetic-tailscale-state' /var/lib/tailscale/tailscaled.state")
    # Do not pass a deliberately invalid fixture to a real tailscaled at boot.
    client.succeed("rm /run/solo-client/ventoy/solo-client/tailscaled.state")
    client.succeed("rm /var/lib/tailscale/tailscaled.state")

    client.succeed("rm /etc/NetworkManager/system-connections/solo-ci.nmconnection")
    client.reboot()
    client.wait_for_unit("multi-user.target")
    client.wait_for_unit("NetworkManager.service")

    # The USB COW overlay persists across guest reboot in the SAME QEMU VM.
    client.succeed("mountpoint -q /run/solo-client/ventoy")
    client.succeed("grep -Fx 'psk=ci-test-password' /etc/NetworkManager/system-connections/solo-ci.nmconnection")
    client.succeed("test \"$(solo-client-state get-host)\" = solo-ci-server")
    client.succeed("nmcli -t -f NAME con show | grep -Fx 'solo-ci-wifi'")
  '';
}
