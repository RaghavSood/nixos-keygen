{
  description = "Minimal NixOS ISO with graphical environment, cowsay, and vanitygen";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.minimal-iso = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ config, pkgs, lib, ... }: let
          vanitygen = pkgs.stdenv.mkDerivation rec {
            pname = "vanitygen";
            version = "0.21";
          
            src = pkgs.fetchgit {
              url = "https://github.com/samr7/vanitygen";
              rev = "refs/tags/${version}";
              sha256 = "1vzfv74hhiyrrpvjca8paydx1ashgbgn5plzrx4swyzxy1xkamah";
            };
          
            patches = [
              (pkgs.fetchpatch {
                name = "openssl-modern";
                url = "https://github.com/RaghavSood/vanitygen/commit/f0dfc1040732e0a9843e0efa2906bd25748382aa.patch";
                sha256 = "sha256-EmCtW9N5l10WAMyTFiVhrM5Ocjqza1WoJsDLRYb04bo=";
              })
            ];
          
            buildInputs = with pkgs; [ openssl pcre ];
          
            installPhase = ''
              mkdir -p $out/bin
              cp vanitygen $out/bin
              cp keyconv $out/bin/vanitygen-keyconv
            '';
          };

	  iancolemanFile = pkgs.runCommand "iancoleman-file" {
	    src = pkgs.fetchurl {
	      url = "https://github.com/iancoleman/bip39/releases/download/0.5.6/bip39-standalone.html";
	      hash = "sha256-EpsDUFgkh5uKRClXbj3mlRyFmWRMGvyq6AhA95I3aVo=";
	    };
	  } ''
	    mkdir -p $out/
	    cp -R $src $out/
	  '';

	  bitaddressFiles = pkgs.runCommand "bitaddress-files" {
            src = pkgs.fetchzip {
              url = "https://github.com/pointbiz/bitaddress.org/archive/v3.3.0.zip";
              sha256 = "sha256-vIANUq8rFd54oI4VpZh1GNUfIOl/hfEMNnoUGItMFGc=";
            };
          } ''
            mkdir -p $out/
            cp -R $src/* $out/
          '';
        in {
          imports = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
            "${nixpkgs}/nixos/modules/profiles/all-hardware.nix"
          ];

          # Adds terminus_font for people with HiDPI displays
          console.packages = [ pkgs.terminus_font ];

          # ISO naming.
          isoImage.isoName = "${config.isoImage.isoBaseName}-keygen-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.iso";

          # Add Memtest86+ to the CD.
          boot.loader.grub.memtest86.enable = true;

          # An installation media cannot tolerate a host config defined file
          # system layout on a fresh machine, before it has been formatted.
          swapDevices = lib.mkForce [ ];
          fileSystems = lib.mkForce config.lib.isoFileSystems;

          boot.postBootCommands = ''
            for o in $(</proc/cmdline); do
              case "$o" in
                live.nixos.passwd=*)
                  set -- $(IFS==; echo $o)
                  echo "nixos:$2" | ${pkgs.shadow}/bin/chpasswd
                  ;;
              esac
            done
          '';

          system.stateVersion = lib.mkDefault lib.trivial.release;

	  # Include bitaddress files in the system
          system.extraDependencies = [ bitaddressFiles ];

          # Enable graphical environment
          services.xserver = {
            enable = true;
            displayManager.lightdm.enable = true;
            desktopManager.xfce.enable = true;
          };

          environment.systemPackages = with pkgs; [
            vim
            jq

	    ungoogled-chromium
	    abiword

            vanitygen
            electrum
            libbitcoin-explorer

	    qrencode

	    dieharder
          ];
	
	  environment.xfce.excludePackages = with pkgs.xfce; [ 
	    parole
	    xfce4-screensaver
	    xfce4-volumed-pulse
	    xfce4-pulseaudio-plugin
	  ];

          # Disable wifi
          networking.wireless.enable = pkgs.lib.mkForce false;

          # Disable network manager to ensure no internet access is required
          networking.networkmanager.enable = false;
	  networking.useDHCP = false;
	  networking.interfaces = {};

          # Remove docs to save space
          documentation.enable = pkgs.lib.mkForce false;
          documentation.nixos.enable = pkgs.lib.mkForce false;
          documentation.doc.enable = pkgs.lib.mkForce false;

          # enable printers
          services.printing.enable = true;
	  services.printing.drivers = with pkgs; [
	    gutenprint
	    hplip
	    brlaser
	  ];

          # We don't need to support installation
          boot.supportedFilesystems = pkgs.lib.mkForce [ ];

          # Use less privileged nixos user
          users.users.nixos = {
            isNormalUser = true;
            extraGroups = [ "wheel" "networkmanager" "video" "lp" ];
            # Allow the graphical user to login without password
            initialHashedPassword = "";
          };

          users.users.root.initialHashedPassword = "";

          # Don't require sudo/root to `reboot` or `poweroff`.
          security.polkit.enable = true;

          # Allow passwordless sudo from nixos user
          security.sudo = {
            enable = lib.mkDefault true;
            wheelNeedsPassword = lib.mkForce false;
          };
        
          # Automatically log in at the virtual consoles.
          services.getty.autologinUser = "nixos";

          nix.settings.trusted-users = [ "nixos" ];

          services.speechd.enable = false;

          # Disable installation-related services
          systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ ];
          systemd.services.nixos-manual.enable = false;

	  system.activationScripts.nixos-home = ''
	    mkdir -p /var/www/tools/{bitaddress,iancolemanbip39}
	    cp --recursive ${bitaddressFiles} /var/www/tools/bitaddress
	    cp ${iancolemanFile} /var/www/tools/iancolemanbip39/iancoleman.html
          '';

          # ISO image configuration
          isoImage = {
            makeEfiBootable = true;
            makeUsbBootable = true;
          };
        })
      ];
    };

    # Build the ISO
    packages.x86_64-linux.default = self.nixosConfigurations.minimal-iso.config.system.build.isoImage;
  };
}
