{ config, lib, pkgs, ... }:

{
  hardware.pulseaudio.enable = lib.mkForce false;
  services.jack.jackd.enable = lib.mkForce false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    jack.enable = true;
    pulse.enable = true;
    media-session.config.bluez-monitor = {
      bluez5.msbc-support = true;
      bluez5.sbc-xq-support = true;
    };
  };

  xdg.portal = {
    enable = true;
    gtkUsePortal = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  environment.systemPackages = with pkgs; [
    # ALSA Tools
    # ------
    alsaUtils

    # PulseAudio control
    # ------------------
    ncpamixer
    pavucontrol
    pulseeffects-pw
    lxqt.pavucontrol-qt
    pasystray
  ];
}
