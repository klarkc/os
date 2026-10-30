{
  description = "Disposable Dell thin client and CPU-only GCE NixOS workstation";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      mk = modules: nixpkgs.lib.nixosSystem { inherit system modules; };
      # The Dell Inspiron i14-5458-D08P shipped with Qualcomm 9565 /
      # Dell Wireless 1707 (ath9k), while some Inspiron 5458 variants
      # use Intel 3160/7265. Keep Broadcom/Realtek/older QCA fallbacks
      # for exchanged cards and USB adapters, but not 2020s Wi-Fi/GPU
      # payloads unrelated to the Broadwell Dell.
      # References: Dell Wireless 1707/Qualcomm 9565 driver 46G81 and
      # Dell Intel Dual Band Wireless AC 3160/7265 driver WRRMC.
      slimFirmware = pkgs.runCommand "lpklarkc-essential-firmware" { } ''
        set -eu
        mkdir -p "$out/lib/firmware/i915"
        source="${pkgs.linux-firmware}/lib/firmware"
        # Broadwell i3-5005U/Intel HD Graphics 5500: retain firmware
        # for Haswell/Broadwell and adjacent Skylake only.
        for item in "$source"/i915/hsw* "$source"/i915/bdw* "$source"/i915/skl*; do
          [ -e "$item" ] || continue
          cp -aL -- "$item" "$out/lib/firmware/i915/"
        done
        # WLAN model variations and 2015-era replacement cards.
        for item in \
          "$source"/iwlwifi-3160-* "$source"/iwlwifi-3165-* \
          "$source"/iwlwifi-7260-* "$source"/iwlwifi-7265* \
          "$source"/iwlwifi-8000C-* "$source"/iwlwifi-8265-* \
          "$source"/brcm "$source"/rtlwifi "$source"/rtl_bt \
          "$source"/rtl_nic "$source"/ath9k_htc "$source"/ath10k \
          "$source"/qca "$source"/ar3k "$source"/intel \
          "$source"/LICENCE* "$source"/LICENSE*; do
          [ -e "$item" ] || continue
          cp -aL -- "$item" "$out/lib/firmware/"
        done
        # Fail the build rather than silently lose the Intel WLAN fallback
        # or proprietary firmware for frequently installed Dell adapters.
        test -n "$(find "$out/lib/firmware" -maxdepth 1 -name 'iwlwifi-3160-*' -print -quit)"
        test -n "$(find "$out/lib/firmware" -maxdepth 1 -name 'iwlwifi-7265*' -print -quit)"
        test -d "$out/lib/firmware/brcm"
        test -d "$out/lib/firmware/qca"
        test ! -e "$out/lib/firmware/ath12k"
      '';
      isoModule = { modulesPath, lib, ... }:
        let
          # Only a build dependency. No splash daemon or image editor is
          # installed on the thin client itself.
          splash = pkgs.runCommand "lpklarkc-boot-splash.png"
            { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
              magick -size 1024x768 xc:'#101820' "$out"
            '';
        in {
          # An RDP appliance does not need the NixOS installer profile,
          # its Nixpkgs source channel or all system repair packages.
          imports = [
            (modulesPath + "/installer/cd-dvd/iso-image.nix")
            (modulesPath + "/profiles/minimal.nix")
          ];

          # Only modules required for USB/ISO boot, SATA/NVMe and QEMU.
          # The generic installer embeds firmware for hundreds of devices.
          hardware.enableAllHardware = false;
          hardware.enableRedistributableFirmware = false;
          hardware.wirelessRegulatoryDatabase = true;
          hardware.firmware = [ slimFirmware ];
          boot.initrd.availableKernelModules = [
            "xhci_pci" "ehci_pci" "usb_storage" "uas" "sd_mod"
            "ahci" "nvme" "virtio_pci" "virtio_blk" "virtio_scsi"
          ];
          isoImage.makeBiosBootable = true;
          isoImage.makeEfiBootable = true;
          isoImage.makeUsbBootable = true;
          isoImage.isoName = "lpklarkc-x86_64.iso";
          # The NixOS ISO builder names its derivation from image.baseName.
          image.baseName = lib.mkForce "lpklarkc-x86_64";

          # Previously supplied by installation-device.nix. Keep only the
          # kiosk account and the TTY recovery path (not installer packages).
          users.users.nixos = {
            isNormalUser = true;
            extraGroups = [ "networkmanager" "video" ];
            initialHashedPassword = "";
          };
          services.getty.autologinUser = "nixos";
          security.sudo.enable = true;
          security.sudo.wheelNeedsPassword = true;
          isoImage.grubTheme = null;
          isoImage.splashImage = splash;
          isoImage.efiSplashImage = splash;
          isoImage.appendToMenuLabel = "";
          system.nixos.distroName = lib.mkForce "lpklarkc";
          # BIOS syslinux TIMEOUT 0 means *no* timeout; use 1 second for
          # reliable automatic boot on both legacy BIOS and UEFI machines.
          boot.loader.timeout = lib.mkForce 1;
        };
      gceModule = { modulesPath, ... }: {
        imports = [ (modulesPath + "/virtualisation/google-compute-image.nix") ];
      };
    in
    {
      nixosConfigurations.lpklarkc = mk [ isoModule ./thin-client.nix ];
      nixosConfigurations.gcp-workstation = mk [ gceModule ./gcp-workstation.nix ];

      packages.${system} = {
        lpklarkc-iso = self.nixosConfigurations.lpklarkc.config.system.build.isoImage;
        gce-image = self.nixosConfigurations.gcp-workstation.config.system.build.googleComputeImage;
      };

      checks.${system} = {
        # Boots BOTH client and server in disposable QEMU VMs, not merely
        # evaluating a Nix expression. No credentials or cloud resources.
        ventoy-usb-persistence-vm = import ./tests/ventoy-persistence.nix { inherit pkgs; };

        boot-and-network-vm = pkgs.testers.runNixOSTest {
          name = "lpklarkc-and-workstation";
          nodes = {
            client = { lib, ... }: {
              imports = [ ./thin-client.nix ];
              users.users.nixos = {
                isNormalUser = true;
                extraGroups = [ "wheel" "networkmanager" "video" ];
                initialPassword = "test-only";
              };
              security.sudo.wheelNeedsPassword = true;
              # Real USB devices are intentionally absent; persistence must
              # fail closed instead of touching an internal VM disk.
              virtualisation.memorySize = 2048;
              virtualisation.graphics = true;
              services.xserver.videoDrivers = [ "modesetting" ];
              # Exercise rootless Xorg via getty@tty1 and startx without any
              # display manager or WM. Production launches xfreerdp only
              # after IAP; here use a local no-network X11 probe.
              environment.loginShellInit = lib.mkForce ''
                if [ "$(id -un)" = "nixos" ] && [ "$(tty)" = "/dev/tty1" ] &&
                   [ ! -e /tmp/lpklarkc-graphics-ok ]; then
                  ${pkgs.xinit}/bin/startx ${pkgs.writeShellScript "lpklarkc-x11-probe" ''
                    test -n "$DISPLAY" || exit 1
                    ${pkgs.coreutils}/bin/printf '%s\n' "$DISPLAY" > /tmp/lpklarkc-graphics-ok
                    ${pkgs.coreutils}/bin/sleep 5
                  ''} -- :0 vt1 -keeptty -nolisten tcp
                fi
              '';
              system.stateVersion = "26.05";
            };
            server = { lib, ... }: {
              imports = [ ./gcp-workstation.nix ];
              # The production image uses GCE OS Login for SSH.
              # Here only exercise native services in a normal VM.
              virtualisation.memorySize = 2048;
              virtualisation.graphics = true;
              system.stateVersion = "26.05";
            };
          };
          testScript = ''
            start_all()
            client.wait_for_unit("multi-user.target")
            server.wait_for_unit("multi-user.target")
            client.succeed("systemctl is-active NetworkManager.service")
            client.succeed("! systemctl is-active --quiet display-manager.service")
            client.succeed("test -e /run/current-system/sw/bin/startx")
            # The login TTY must actually launch a rootless Xorg screen.
            client.wait_until_succeeds("test -s /tmp/lpklarkc-graphics-ok", timeout=180)
            client.succeed("grep -Fx :0 /tmp/lpklarkc-graphics-ok")
            # User PipeWire runs with tty1 autologin; no physical audio card
            # is needed to assert an active PipeWire/Pulse-compatible socket.
            client.succeed("test -d /run/current-system/sw/share/icons")
            client.succeed("test -e /run/current-system/sw/bin/pw-cli")
            client.wait_until_succeeds("test -S /run/user/$(id -u nixos)/pulse/native", timeout=180)
            client.wait_until_succeeds(
              "runuser -u nixos -- env XDG_RUNTIME_DIR=/run/user/$(id -u nixos) /run/current-system/sw/bin/pw-cli info 0 >/dev/null",
              timeout=180
            )
            client.succeed("test -e /run/current-system/sw/bin/lpklarkc-iap")
            client.succeed("test -e /run/current-system/sw/bin/lpklarkc-peer-watchdog")
            # VM runs mocked GCE lifecycle and conservative watchdog offline,
            # proving none of these tests can start, stop or bill a VM.
            client.succeed("${pkgs.bash}/bin/bash ${./tests/gce-lifecycle.sh} ${./scripts/gce-iap.sh}")
            client.succeed("${pkgs.bash}/bin/bash ${./tests/client-peer-watchdog-test.sh} ${./scripts/client-peer-watchdog.sh} ${./scripts/thin-client.sh}")
            client.succeed("test -e /run/current-system/sw/bin/gcloud")
            client.succeed("! test -e /run/current-system/sw/bin/lpklarkc-wg")
            client.succeed("! systemctl is-active --quiet tailscaled.service")
            client.succeed("systemctl show -P Result lpklarkc-ventoy-state.service | grep -Fx success")
            client.succeed("test -e /run/current-system/sw/bin/lpklarkc-state")
            client.succeed("test -e /run/current-system/sw/bin/xfreerdp")
            client.succeed("! mountpoint -q /run/lpklarkc/ventoy")
            client.succeed("test ! -d /run/lpklarkc/ventoy/lpklarkc")
            client.succeed("! test -e /home/nixos/.config/lpklarkc-gcloud/credentials.db")
            client.succeed("systemctl start lpklarkc-save-state.service")
            server.succeed("systemctl is-active xrdp.service")
            server.succeed("systemctl is-active xrdp-sesman.service")
            # Server is managed independently by BuildGCE. Do not assert
            # its legacy Tailscale status as part of the client contract.
            server.succeed("id klarkc")
            server.succeed("test -d /home/klarkc")
            server.succeed("ss -lnt | grep ':3389'")
          '';
        };
      };
    };
}
