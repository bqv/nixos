{ modulesPath, ... }: {
  imports = [
    # passwd is nixos by default
    ../../users/nixos.nix
    # passwd is empty by default
    ../../users/root.nix
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
  ];

  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  networking.networkmanager.enable = true;
}
