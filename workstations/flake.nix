{
  description = "Disposable Dell thin client and CPU-only GCE NixOS workstation";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      # The test harness supplies an already-imported, read-only pkgs.
      # Whitelist ONLY official Firefox at import time, never by setting
      # nixpkgs.config in thin-client.nix (which conflicts in QEMU).
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate =
          pkg: builtins.elem (nixpkgs.lib.getName pkg)
            [ "firefox-bin" "firefox-bin-unwrapped" ];
      };
      mk = modules: nixpkgs.lib.nixosSystem { inherit system modules; };
      # General-purpose live boot: use the supported NixOS hardware profile
      # instead of a Dell-specific, manually curated firmware derivation.
      # This includes modern Intel/AMD/NVIDIA-open GPU firmware, Wi-Fi
      # adapters and storage controllers where redistribution is allowed.
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

          # Generic x86_64 live CD: NixOS' all-hardware profile includes
          # broad boot-controller drivers and redistributable firmware for
          # different generations/vendors of laptops. No internal install.
          hardware.enableAllHardware = true;
          hardware.enableRedistributableFirmware = true;
          hardware.wirelessRegulatoryDatabase = true;
          # Explicit baseline USB modules for a Ventoy live boot; the broad
          # all-hardware profile ADDITIVELY supplies many more controllers.
          boot.initrd.availableKernelModules = [
            "xhci_pci" "ehci_pci" "usb_storage" "uas" "sd_mod"
            "ahci" "nvme" "virtio_pci" "virtio_blk" "virtio_scsi"
          ];
          isoImage.makeBiosBootable = true;
          isoImage.makeEfiBootable = true;
          isoImage.makeUsbBootable = true;
          isoImage.isoName = "lpklarkc-x86_64.iso";
          # Keep XZ compression for a portable, non-installing live image.
          # Generic redistributable firmware + Mesa can increase the ISO;
          # the existing CI size gate remains explicit and measurable.
          isoImage.squashfsCompression = "xz -Xdict-size 100% -Xbcj x86";
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
          # The default generic live image MUST continue accepting internal
          # keyboards on other laptops. Only this explicitly selected Dell
          # BIOS/EFI boot option bypasses the broken internal PS/2 keyboard.
          # i8042.nokbd does not disable USB HID/xHCI and does not cover I2C.
          specialisation.dell-internal-keyboard-off.configuration = {
            boot.kernelParams = [ "i8042.nokbd" ];
            isoImage.configurationName = "Dell internal keyboard OFF (USB required)";
          };
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
      # Production ISO and QEMU test nodes share the exact same configured
      # pkgs so Firefox licensing does not redefine read-only nixpkgs.config.
      nixosConfigurations.lpklarkc = nixpkgs.lib.nixosSystem {
        inherit system pkgs;
        modules = [ isoModule ./thin-client.nix ];
      };
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
            client = { config, lib, ... }: {
              imports = [ ./thin-client.nix ];
              # qemu-vm.nix normally uses mkVMOverride (priority 10) to
              # reduce videoDrivers to modesetting. In this test ONLY, use
              # priority 9 so the VM exercises the *evaluated* driver list
              # of the real generic ISO, including optional legacy DDX.
              # A failing full-list QEMU test is evidence, not a release.
              services.xserver.videoDrivers = lib.mkOverride 9
                self.nixosConfigurations.lpklarkc.config.services.xserver.videoDrivers;
              assertions = [{
                assertion = config.services.xserver.videoDrivers ==
                  self.nixosConfigurations.lpklarkc.config.services.xserver.videoDrivers;
                message = "QEMU Xorg videoDrivers differ from production generic ISO";
              }];
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
              # Exercise the SAME auto-detected Xorg driver list as the actual
              # portable live ISO. Do not force modesetting in the QEMU test.
              # Exercise rootless Xorg via getty@tty1 and startx without any
              # display manager or WM. Production launches xfreerdp only
              # after IAP; here use a local no-network X11 probe.
              environment.loginShellInit = lib.mkForce ''
                if [ "$(id -un)" = "nixos" ] && [ "$(tty)" = "/dev/tty1" ] &&
                   [ ! -e /tmp/lpklarkc-graphics-ok ]; then
                  ${pkgs.xinit}/bin/startx ${pkgs.writeShellScript "lpklarkc-x11-probe" ''
                    test -n "$DISPLAY" || exit 1
                    # Prove a real X11 server exposes a screen, not just DISPLAY.
                    ${pkgs.xdpyinfo}/bin/xdpyinfo -display "$DISPLAY" > /tmp/lpklarkc-xdpyinfo.txt || exit 1
                    ${pkgs.gnugrep}/bin/grep -Eq '^screen #0:' /tmp/lpklarkc-xdpyinfo.txt || exit 1
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
            # Real X11 protocol/screen proof and actual rootless driver loader log.
            client.succeed("grep -Eq '^screen #0:' /tmp/lpklarkc-xdpyinfo.txt")
            client.wait_until_succeeds("test -s /home/nixos/.local/share/xorg/Xorg.0.log", timeout=180)
            client.succeed("grep -Eq 'LoadModule: \"(modesetting|intel|amdgpu|nouveau|vesa)\"' /home/nixos/.local/share/xorg/Xorg.0.log")
            # Preserve the negative DDX ABI/no-screens gate. On failure
            # capture the *actual* matching lines and related loader context
            # before returning nonzero, so CI distinguishes a rejected
            # fallback module from a fatal active-screen regression.
            client.succeed("""
              bash -c '
                log=/home/nixos/.local/share/xorg/Xorg.0.log
                if grep -Eiq "undefined symbol|no screens found" "$log"; then
                  echo "XORG_DDX_NEGATIVE_GATE_FAILED: matching log lines:"
                  grep -Ein -B 6 -A 6 "undefined symbol|no screens found" "$log" | head -n 160 || true
                  echo "XORG_DDX_LOADER_AND_SCREEN_CONTEXT:"
                  grep -Ein "LoadModule:|Loading /|UnloadModule:|module ABI|modesetting|intel|nouveau|amdgpu|vesa|drm|screen" "$log" | tail -n 120 || true
                  exit 1
                fi
              '
            """)
            # Xorg protocol success alone cannot prove DRM/KMS device creation.
            # Probe live guest cardN (not a fixed card0 ordinal) and its bound
            # kernel driver. QEMU virtio DRM is NOT physical Dell Intel i915.
            drm_binding = client.succeed("""
              bash -e -c '
                for node in /dev/dri/card[0-9]*; do
                  [ -c "$node" ] || continue
                  card="$(basename "$node")"
                  sys="/sys/class/drm/$card"
                  [ -r "$sys/dev" ] || continue
                  major="$(cut -d: -f1 "$sys/dev")"
                  [ "$major" = 226 ] || continue
                  driver="$(readlink -e "$sys/device/driver" 2>/dev/null)" || continue
                  [ -n "$driver" ] || continue
                  printf "card=%s major=%s driver=%s" "$card" "$major" "$driver"
                  exit 0
                done
                echo "No major-226 DRM cardN with kernel driver binding" >&2
                exit 1
              '
            """)
            print("QEMU DRM/KMS device evidence: " + drm_binding)
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
            client.succeed("test -x /run/current-system/sw/bin/lpklarkc-oauth-session")
            client.succeed("test -x /run/current-system/sw/bin/lpklarkc-oauth-browser")
            # Local Google OAuth is mocked; the rootless Xorg startup is
            # independently verified above. No account or cloud API needed.
            client.succeed("runuser -u nixos -- ${pkgs.bash}/bin/bash ${./tests/oauth-local-test.sh} ${./scripts/gce-iap.sh} ${./scripts/oauth-session.sh} ${./scripts/oauth-browser.sh}")
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
