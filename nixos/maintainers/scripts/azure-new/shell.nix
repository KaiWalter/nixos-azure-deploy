{pkgs ? import ../../../../default.nix {} }:

pkgs.stdenv.mkDerivation {
  buildInputs = with pkgs; [
    azure-cli
    bash
    # TODO What is cacert used for?
    # Probably because Azure CLI needs SSL certs, and
    # https://gist.github.com/CMCDragonkai/1ae4f4b5edeb021ca7bb1d271caca999
    cacert
    azure-storage-azcopy
    jq
  ];

  name = "azure-nixos";

  shellHook = ''
    export AZURE_CONFIG_DIR="$HOME/.azure" 
    export AZURE_NEW_PKGS_PATH=pkgs.path;
  '';
}
