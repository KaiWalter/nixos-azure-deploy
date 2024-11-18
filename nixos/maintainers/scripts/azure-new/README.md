## Working Approach

```
nix-channel --add https://channels.nixos.org/nixos-24.05 nixpkgs
nix-channel --update
nix-shell --arg pkgs 'import <nixpkgs> {}'
./upload-image.sh -g kw-nixos -n kw-nixos-v1 -i ./kw-nixos/image.nix -l swedencentral
./boot-vm.sh -g kw-nixos -i kw-nixos-v1 -l swedencentral -n kw-nixos -s Standard_B4ms -d 10
```
