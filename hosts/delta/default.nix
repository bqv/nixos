{ config, lib, pkgs, usr, flake, system, hosts, ... }:

{
  imports = [
    ../../profiles/meta/fatal-warnings.nix
    ../../profiles/misc/disable-mitigations.nix
    ../../profiles/misc/udev-nosettle.nix
    ../../profiles/misc/adblocking.nix
    ../../profiles/misc/odbc.nix
    ../../profiles/security/sudo.nix
   #../../profiles/security/apparmor
    ../../profiles/services/syncthing
    ../../profiles/services/aria2
    ../../profiles/services/guix
    ../../profiles/services/searx
    ../../profiles/services/hydra
    ../../profiles/networking/ipfs
    ../../profiles/networking/bluetooth
    ../../profiles/networking/wireguard
    ../../profiles/networking/mdns.nix
    ../../profiles/sound/pipewire.nix
    ../../profiles/virtualization/anbox
    ../../profiles/graphical
    ../../profiles/games
    ../../profiles/bcachefs.nix
    ../../profiles/wayland.nix
    ../../profiles/weechat.nix
    ../../users/root.nix
    ../../users/bao.nix
    ./xserver.nix
    ./network.nix
    ./remote.nix
  ];

  platform = "x86_64-linux";

  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    grub = {
      enable= true;
      device = "nodev";
     #efiInstallAsRemovable = true;
      efiSupport = true;
      memtest86.enable = true;
      useOSProber = true;
      configurationLimit = 64;
    };
    efi.canTouchEfiVariables = true;
    systemd-boot = {
      enable = false;
      configurationLimit = 64;
      memtest86.enable = true;
    };
  };

  boot.initrd.availableKernelModules = [
    "xhci_pci" "ehci_pci" "ahci" "usbcore"
    "sd_mod" "sr_mod" "nvme" "amdgpu"
  ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.initrd.secrets = {
    "/etc/nixos" = lib.cleanSource ./../..;
  };
  boot.kernelModules = [ "kvm-intel" "amdgpu" "fuse" ];
  boot.kernelParams = [ "mce=3" ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
  boot.binfmt.emulatedSystems = [ "armv7l-linux" "aarch64-linux" ];
  boot.postBootCommands = ''
   #echo 0000:04:00.0 > /sys/bus/pci/drivers/xhci_hcd/unbind
  ''; # usb4 is faulty
  boot.tmpOnTmpfs = false;

  fileSystems = let
    hdd = {
      device = "/dev/disk/by-uuid/f61d5c96-14db-4684-9bd6-218a468433b2";
      fsType = "btrfs";
    };
    ssd = {
      device = "/dev/sda2";
      fsType = "btrfs";
    };
  in {
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = [ "defaults" "size=8G" "mode=755" "nr_inodes=8M" ];
    };

    "/var" = hdd // { options = [ "subvol=var" ]; };
    "/home" = hdd // { options = [ "subvol=home" ]; };
    "/srv" = hdd // { options = [ "subvol=srv" ]; };
    "/nix" = ssd // { options = [ "noatime" "nodiratime" "discard=async" ]; };
    "/gnu" = ssd // { options = [ "noatime" "nodiratime" "discard=async" "subvol=gnu" ]; };
    "/games" = hdd // { options = [ "subvol=games" ]; };
    "/run/hdd" = hdd // { options = [ "subvolid=0" ]; };
    "/run/ssd" = ssd // { options = [ "subvolid=0" "noatime" "nodiratime" "discard=async" ]; };

    ${config.services.ipfs.dataDir} = hdd // { options = [ "subvol=ipfs" ]; };

    "/boot" = {
      device = "/dev/disk/by-uuid/4305-4121";
      fsType = "vfat";
    };
  };
  systemd.services.srv-facl = {
    after = [ "srv.mount" ];
    script = "${pkgs.acl}/bin/setfacl -Rdm g:users:rwX /srv";
    wantedBy = [ "local-fs.target" ];
  };
  systemd.mounts = lib.mkForce [];

  swapDevices = [
   #{ device = "/dev/disk/by-uuid/86868083-921c-452a-bf78-ae18f26b78bf"; }
  ];

  virtualisation.libvirtd.enable = true;
  virtualisation.virtualbox.host.enable = false;
  virtualisation.anbox.enable = true;
  systemd.network.networks = lib.mkIf config.virtualisation.anbox.enable {
    "40-anbox0".networkConfig.ConfigureWithoutCarrier = true;
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  headless = false;

  nix = {
    gc.automatic = false; # We'll just use min-free instead
    gc.dates = "12:00"; # I'm now conditioned to be scared of midday
    gc.options = "--delete-older-than 8d";

    autoOptimiseStore = false; # Disabled for speed
    optimise.automatic = true;
    optimise.dates = [ "17:30" "02:00" ];

    maxJobs = 8;
    nrBuildUsers = 64;

    sandboxPaths = [ "/bin/sh=${pkgs.bash}/bin/sh" ];
    extraOptions = with usr.units; ''
      min-free = ${toString (gigabytes 48)}
    '';

    systemFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    buildMachines =
     #(lib.optional true {
     #  hostName = "localhost";
     #  #system = "x86_64-linux";
     #  systems = ["x86_64-linux" "i686-linux" ] ++ config.boot.binfmt.emulatedSystems;
     #  inherit (config.nix) maxJobs;
     #  speedFactor = 4;
     #  supportedFeatures = config.nix.systemFeatures;
     #  mandatoryFeatures = [ ];
     #})++
      (lib.optional true {
        hostName = hosts.wireguard.ipv4.zeta;
        #sshUser = "nix-ssh";
        sshKey = "/etc/nix/id_zeta.ed25519";
        systems = ["x86_64-linux" "i686-linux" "armv6l-linux" "armv7l-linux"];
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
        mandatoryFeatures = [ ];
      }) ;
    distributedBuilds = true;
  };

  hardware.ckb-next.enable = true;
  hardware.opengl.driSupport32Bit = true;
  hardware.cpu = {
    intel.updateMicrocode = true;
    amd.updateMicrocode = true;
  };

  programs.firejail = {
    enable = true;
    wrappedBinaries = builtins.mapAttrs (k: builtins.toPath) {
      firefox-safe-x11 = pkgs.writeScript "firefox" ''
        env MOZ_ENABLE_WAYLAND=1 ${lib.getBin pkgs.firefox}/bin/firefox
      '';
      firefox-safe-wl = pkgs.writeScript "firefox" ''
        env -u MOZ_ENABLE_WAYLAND ${lib.getBin pkgs.firefox}/bin/firefox
      '';
      chromium-safe = "${lib.getBin pkgs.chromium}/bin/chromium";
      teams-safe = "${lib.getBin pkgs.teams}/bin/teams"; # broken a.f.
      mpv-safe = "${lib.getBin pkgs.mpv}/bin/mpv"; # broken too, apparently
    };
  };
  programs.vim.defaultEditor = true;
  programs.adb.enable = true;
  programs.tmux.enable = true;
  programs.xonsh.enable = true;
  programs.singularity.enable = true;

  services.printing.enable = true;
  services.nix-index.enable = true;
  services.locate.enable = true;
  services.pcscd.enable = true;
  services.flatpak.enable = true;
  xdg.portal.enable = true;
  services.searx.enable = true;
  services.hydra.enable = false; # disabled because holy wtf
  services.flake-ci.enable = true;
  services.grocy.enable = true;
  services.gitfs = {
    enable = true;
    mounts = {
      nixrc = {
        directory = "/run/git/nixrc";
        remote = "/srv/git/github.com/bqv/nixrc";
        branch = "substrate";
      };
     #"/run/git/nixpkgs" = {
     #  github.owner = "nixos";
     #  github.repo = "nixpkgs";
     #};
    };
  };
  services.minecraft-server = {
    enable = true;
    eula = true;
    package = pkgs.papermc;
    declarative = true;
    serverProperties = {
      motd = "Kany0 City";
      server-port = 25565;
      difficulty = 1;
      gamemode = "survival";
      max-players = 16;
      enable-rcon = true;
      "rcon.password" = "ihaveafirewalldude";
    };
  };
  services.biboumi = {
    enable = true;
    settings = {
      admin = [ "qy@${usr.secrets.domains.srvc}" ];
      hostname = "irc.${usr.secrets.domains.srvc}";
     #outgoing_bind = localAddress6;
      password = usr.secrets.weechat.credentials.password;
      port = 5347;
      xmpp_server_ip = usr.secrets.hosts.wireguard.ipv4.zeta;
    };
  };

 #security.pam.loginLimits = [
 #  { domain = "@wheel"; item = "nofile"; type = "hard"; value = "unlimited"; }
 #  { domain = "@wheel"; item = "nofile"; type = "soft"; value = "1048576"; }
 #];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYNqRbITjMHmgD/UC87BISFTaw7Tq1jNd8X8i26x4b5 root@delta"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvcvk1nLYImKqjhL8HdAb1sM2vXcEGu+rMZJ8XIG4H7 bao@delta"
  ];

  environment.systemPackages = with pkgs; [
    clipmenu bitwarden bitwarden-cli pass protonmail-bridge
    nix-bundle nix-output-monitor

    ckb-next profanity dino element-desktop nheko discord ripcord
    brave vivaldi vivaldi-ffmpeg-codecs vivaldi-widevine
    qutebrowser firefox thunderbird electronmail mpv apvlv

    dunst catt termite rxvt_unicode
    steam obs-studio epsxe

    virt-manager anbox #pmbootstrap

    (with hunspellDicts; hunspellWithDicts [ en_GB-large ])
    wineWowPackages.staging

    giara lbry haskellPackages.hnix

    python3.pkgs.fritzconnection mactelnet wold
  ];

  environment.etc."nix/id_zeta.ed25519".source = "${usr.secrets.keyDir}/nix/id_zeta.ed25519";
  environment.etc."nix/id_zeta.ed25519".mode = "0400";
  environment.etc."ssh/ssh_host_rsa_key".source = "${usr.secrets.keyDir}/deltassh/ssh_host_rsa_key";
  environment.etc."ssh/ssh_host_rsa_key".mode = "0400";
  environment.etc."ssh/ssh_host_rsa_key.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_host_rsa_key.pub";
  environment.etc."ssh/ssh_host_ed25519_key".source = "${usr.secrets.keyDir}/deltassh/ssh_host_ed25519_key";
  environment.etc."ssh/ssh_host_ed25519_key".mode = "0400";
  environment.etc."ssh/ssh_host_ed25519_key.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_host_ed25519_key.pub";
  environment.etc."ssh/ssh_host_dsa_key".source = "${usr.secrets.keyDir}/deltassh/ssh_host_dsa_key";
  environment.etc."ssh/ssh_host_dsa_key".mode = "0400";
  environment.etc."ssh/ssh_host_dsa_key-cert.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_host_dsa_key-cert.pub";
  environment.etc."ssh/ssh_host_dsa_key.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_host_dsa_key.pub";
  environment.etc."ssh/ssh_host_ecdsa_key".source = "${usr.secrets.keyDir}/deltassh/ssh_host_ecdsa_key";
  environment.etc."ssh/ssh_host_ecdsa_key".mode = "0400";
  environment.etc."ssh/ssh_host_ecdsa_key-cert.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_host_ecdsa_key-cert.pub";
  environment.etc."ssh/ssh_host_ecdsa_key.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_host_ecdsa_key.pub";
  environment.etc."ssh/ssh_host_ed25519_key-cert.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_host_ed25519_key-cert.pub";
  environment.etc."ssh/ssh_host_rsa_key-cert.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_host_rsa_key-cert.pub";
  environment.etc."ssh/ssh_revoked_keys".text = "";
  environment.etc."ssh/ssh_user-ca.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_user-ca.pub";
  environment.etc."ssh/ssh_host-ca.pub".source = "${usr.secrets.keyDir}/deltassh/ssh_host-ca.pub";
}
