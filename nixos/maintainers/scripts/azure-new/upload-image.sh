#!/usr/bin/env bash

####################################################
# AZ LOGIN CHECK                                   #
####################################################

# Making  sure  that  one   is  logged  in  (to  avoid
# surprises down the line).
if [ $(az account list | jq -r 'length') -eq 0 ]
then
  echo
  echo '********************************************************'
  echo '* Please log  in to  Azure by  typing "az  login", and *'
  echo '* repeat the "./upload-image.sh" command.              *'
  echo '********************************************************'
  exit 1
fi

####################################################
# HELPERS                                          #
####################################################

show_id() {
  az $1 show \
    --resource-group "${resource_group}" \
    --name "${img_name}"        \
    --query "[id]"              \
    --output tsv
}

# make_boot_sh_opts <image-id> "<opt1>=<val1>;...;<optn>=<valn>"
make_boot_sh_opts() {
  # Add `./upload-image.sh`'s resource group if not given
  # https://stackoverflow.com/a/8811800/1498178 (contains string?)
  if [ "${2#*g=}" != "$2" ] || [ "${2#*resource-group}" != "$2" ]
  then
    opt_string=$2
  else
    opt_string="resource-group=${resource_group};$2"
  fi

  acc=""
  # https://stackoverflow.com/a/918931/1498178 (parse and loop opt-string)
  while IFS=';' read -ra opts; do
    for i in "${opts[@]}"; do
        # https://stackoverflow.com/a/10520718/1498178 (separate opts and vals)
        opt=${i%=*}
        val=${i#*=}
        # https://stackoverflow.com/a/17750975/1498178 (string length)
        # https://stackoverflow.com/a/3953712/1498178 (ternary)
        sep=$([ ${#opt} == 1 ] && echo "-" || echo "--")
        acc="${acc}${sep}${opt} ${val} "
    done
  done <<< "image=$1;$opt_string"

  echo $acc
}

usage() {
  echo ''
  echo 'USAGE: (Every switch requires an argument)'
  echo ''
  echo '-g --resource-group REQUIRED Created if does  not exist. Will'
  echo '                             house a new disk and the created'
  echo '                             image.'
  echo ''
  echo '-n --image-name     REQUIRED The  name of  the image  created'
  echo '                             (and also of the new disk).'
  echo ''
  echo '-i --image-nix      Nix  expression   to  build  the'
  echo '                    image. Default value:'
  echo '                    "./examples/basic/image.nix".'
  echo ''
  echo '-l --location       Values from `az account list-locations`.'
  echo '                    Default value: "uksouth".'
  echo ''
  echo '-b --boot-sh-opts   Run  `./boot-vm.sh`  once   the  image  is'
  echo '                    created and  uploaded; takes  arguments in'
  echo '                    the  format of  "opt1=val1;...;optn=valn".'
  echo '                    (See the  avialable `boot-vm.sh` options'
  echo '                    at section 2.3 below.)'
  echo ''
  echo '                    + "vm-name=..." (or "n=...") is mandatory'
  echo ''
  echo '                    + if   "--image"   (i.e.,   "image=..")   is'
  echo '                      omitted, it will be pre-populated with the'
  echo '                      name of the image just created'
  echo ''
  echo '                    + if  resource group  is omitted,  the one'
  echo '                      for `./upload-image.sh` is used'
  echo ''
  echo '--hyper-g-gen       Hyper-V-Generation V1 or V2. Will be used'
  echo '                    for image SKU.'
  echo '                    Default value: "V1".'
  echo ''
  echo '-v --version        Image Version.'
  echo '                    Default value: "1.0.0".'
  echo ''
  echo '-p --publisher      Image Publisher.'
  echo '                    Default value: "kws".'
  echo ''
  echo '-o --offer          Image Offer.'
  echo '                    Default value: "nixos".'
  echo ''
  echo '-r --gallery-name   Image Gallery Name'
  echo ''
}

####################################################
# SWITCHES                                         #
####################################################

# https://unix.stackexchange.com/a/204927/85131
while [ $# -gt 0 ]; do
  case "$1" in
    -i|--image-nix)
      image_nix="$2"
      ;;
    -l|--location)
      location="$2"
      ;;
    -g|--resource-group)
      resource_group="$2"
      ;;
    -n|--image-name)
      img_name="$2"
      ;;
    -b|--boot-sh-opts)
      boot_opts="$2"
      ;;
    --hyper-g-gen)
      hyper_v_gen="$2"
      ;;
    -v|--version)
      img_version="$2"
      ;;
    -p|--publisher)
      img_publisher="$2"
      ;;
    -o|--offer)
      img_offer="$2"
      ;;
    -r|--gallery-name)
      gallery_name="$2"
      ;;
    -h|--help)
      usage
      exit 1
      ;;
    *)
      printf "***************************\n"
      printf "* Error: Invalid argument *\n"
      printf "***************************\n"
      usage
      exit 1
  esac
  shift
  shift
done

if [ -z "${img_name}" ] || [ -z "${resource_group}" ]
then
  printf "************************************\n"
  printf "* Error: Missing required argument *\n"
  printf "************************************\n"
  usage
  exit 1
fi

####################################################
# DEFAULTS                                         #
####################################################

image_nix_d="${image_nix:-"./kw-nixos/image.nix"}"
location_d="${location:-"uksouth"}"
boot_opts_d="${boot_opts:-"none"}"
gallery_name="${gallery_name:-"kwimages"}"
hyper_v_gen="${hyper_v_gen:-"V1"}"
img_version="${img_version:-"1.0.0"}"
img_publisher="${img_publisher:-"kws"}"
img_offer="${img_offer:-"nixos"}"
img_sku=$hyper_v_gen

if [[ "$hyper_v_gen" != "V1" && "$hyper_v_gen" != "V2" ]]; then
  printf "*************************************\n"
  printf "* Error: invalid Hyper-V-Generation *\n"
  printf "*************************************\n"
  usage
  exit 1
fi

####################################################
# PUT IMAGE INTO AZURE CLOUD                       #
####################################################

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

nix-build             \
  --out-link "azure"  \
  "${image_nix_d}"

# Make resource group exists
if ! az group show --resource-group "${resource_group}" &>/dev/null
then
  az group create     \
    --name "${resource_group}" \
    --location "${location_d}"
fi


if ! az sig show --resource-group "${resource_group}" --gallery-name "${gallery_name}" &>/dev/null
then
   az sig create \
     --resource-group "${resource_group}" \
     --gallery-name "${gallery_name}"
fi

if ! az sig image-definition show --resource-group "${resource_group}" --gallery-name "${gallery_name}" -i "${img_name}" &>/dev/null
then
  az sig image-definition create \
    --resource-group "${resource_group}" \
    --gallery-name "${gallery_name}" \
    -i "${img_name}" \
    --os-type Linux \
    --hyper-v-generation "${hyper_v_gen}" \
    --publisher "${img_publisher}" \
    --offer "${img_offer}" \
    --sku "${img_sku}"
fi


# NOTE: The  disk   access  token   song/dance  is
#       tedious  but allows  us  to upload  direct
#       to  a  disk  image thereby  avoid  storage
#       accounts (and naming them) entirely!

if ! show_id "disk" &>/dev/null
then

  img_file="$(readlink -f ./azure/disk.vhd)"
  bytes="$(stat -c %s ${img_file})"

  az disk create                \
    --resource-group "${resource_group}" \
    --name "${img_name}"        \
    --for-upload true           \
    --upload-size-bytes "${bytes}"

  timeout=$(( 60 * 60 )) # disk access token timeout
  sasurl="$(\
    az disk grant-access               \
      --access-level Write             \
      --resource-group "${resource_group}"      \
      --name "${img_name}"             \
      --duration-in-seconds ${timeout} \
      --query "[accessSas]"            \
      --output tsv
  )"

  azcopy copy "${img_file}" "${sasurl}" \
    --blob-type PageBlob

  # https://docs.microsoft.com/en-us/cli/azure/disk?view=azure-cli-latest#az-disk-revoke-access
  # > Revoking the SAS will  change the state of
  # > the managed  disk and allow you  to attach
  # > the disk to a VM.
  az disk revoke-access         \
    --resource-group "${resource_group}" \
    --name "${img_name}"
fi

if ! show_id "image" &>/dev/null
then
  az image create                \
    --resource-group "${resource_group}"  \
    --name "${img_name}"         \
    --source "$(show_id "disk")" \
    --hyper-v-generation "${hyper_v_gen}"      \
    --os-type "linux"
fi

az sig image-version create \
  --resource-group "${resource_group}" \
  --gallery-name "${gallery_name}" \
  --gallery-image-definition "${img_name}" \
  --gallery-image-version "${img_version}" \
  --managed-image "$(show_id "image")"

if [ "${boot_opts_d}" != "none" ]
then
  img_id="$(show_id "image")"
  ./boot-vm.sh $(make_boot_sh_opts $img_id $boot_opts_d)
fi
