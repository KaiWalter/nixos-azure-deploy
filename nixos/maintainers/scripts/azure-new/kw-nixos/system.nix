{ pkgs, modulesPath, ... }:

let username = "kai";
in
{
  imports = [
    "${modulesPath}/virtualisation/azure-common.nix"
    "${modulesPath}/virtualisation/azure-image.nix"
  ];

  users.users."${username}" = {
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    openssh.authorizedKeys.keys = [ (builtins.readFile ~/.ssh/id_rsa.pub) ];
  };
  # nix.settings.trusted-users = [ username ];
  nix.settings.trusted-users = [ "@wheel" ];

  virtualisation.azureImage.diskSize = 2500;

  system.stateVersion = "24.11";
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # test user doesn't have a password
  services.openssh.settings.PasswordAuthentication = false;
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    git
  ];
}
