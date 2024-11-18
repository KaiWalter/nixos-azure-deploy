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

assign_role() {
  az role assignment create      \
    --assignee "${principal_id}" \
    --role "Owner"               \
    --scope "${group_id}"
}

usage() {
  echo ''
  echo 'USAGE: (Every switch requires an argument)'
  echo ''
  echo '-g --resource-group REQUIRED Created if does  not exist. Will'
  echo '                             house a new disk and the created'
  echo '                             image.'
  echo ''
  echo '-i --image          REQUIRED ID or name of an existing image.'
  echo '                             (See `az image list --output table`)'
  echo '                              or  `az image list --query "[].{ID:id, Name:name}"`.)'
  echo ''
  echo '-n --vm-name        REQUIRED The name of the new virtual machine'
  echo '                             to be created.'
  echo ''
  echo '-s --vm-size        See https://azure.microsoft.com/pricing/details/virtual-machines/ for size info.'
  echo '                    Default value: "Standard_DS1_v2"'
  echo ''
  echo '-d --os-size        OS disk size in GB to create.'
  echo '                    Default value: "42"'
  echo ''
  echo '-l --location       Values from `az account list-locations`.'
  echo '                    Default value: "swedencentral".'
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
  echo 'NOTE: Brand new SSH  keypair is going to  be generated. To'
  echo '      provide  your own,  edit  the very  last command  in'
  echo '      `./boot-vm.sh`.'
  echo ''
};

####################################################
# SWITCHES                                         #
####################################################

# https://unix.stackexchange.com/a/204927/85131
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--location)
      location="$2"
      ;;
    -g|--resource-group)
      resource_group="$2"
      ;;
    -i|--image)
      img_name="$2"
      # case "$2" in
      #   /*)
      #     img_id="$2"
      #     ;;
      #   *)  # image name
      #     img_id="$(az image list             \
      #       --query "[?name=='"$2"'].{ID:id}" \
      #       --output tsv
      #     )"
      #  esac
      ;;
    -n|--vm-name)
      vm_name="$2"
      ;;
    -s|--vm-size)
      vm_size="$2"
      ;;
    -d|--os-disk-size-gb)
      os_size="$2"
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

if [ -z "${img_name}" ] || [ -z "${resource_group}" ] || [ -z "${vm_name}" ]
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

location_d="${location:-"swedencentral"}"
os_size_d="${os_size:-"42"}"
vm_size_d="${vm_size:-"Standard_DS1_v2"}"
gallery_name="${gallery_name:-"kwimages"}"
hyper_v_gen="${hyper_v_gen:-"V1"}"
img_version="${img_version:-"1.0.0"}"
img_publisher="${img_publisher:-"kws"}"
img_offer="${img_offer:-"nixos"}"
img_sku=$hyper_v_gen

case "${img_name}" in
  /*)
    img_id="${img_name}"
    ;;
  *)  # image name
    img_id="$(az sig image-version list \
      -i "${img_name}"                  \
      -r "${gallery_name}"              \
      -g "${resource_group}"            \
      --query "[?name=='"${img_version}"'].id" \
      --output tsv
    )"
esac

img_type="$(az resource show --id "${img_id}" --query type -o tsv)"

if [ "${img_type}" != "Microsoft.Compute/galleries/images/versions" ]
then
  printf "************************************\n"
  printf "* Error: Not a Gallery Image       *\n"
  printf "************************************\n"
  exit 1
fi

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# # Make resource group exists
# if ! az group show --resource-group "${resource_group}" &>/dev/null
# then
#   az group create              \
#     --name "${resource_group}" \
#     --location "${location_d}"
# fi

# (optional) identity
if ! az identity show --name "${resource_group}-identity" --resource-group "${resource_group}" &>/dev/stderr
then
  az identity create                    \
    --name "${resource_group}-identity" \
    --resource-group "${resource_group}"
fi

# (optional) role assignment, to the resource group;
# bad but not really great alternatives
principal_id="$(
  az identity show                       \
    --name "${resource_group}-identity"  \
    --resource-group "${resource_group}" \
    --output tsv --query "[principalId]"
)"

group_id="$(
  az group show                \
    --name "${resource_group}" \
    --output tsv               \
    --query "[id]"
)"

# As long as the `az role assignment` command fails,
# the loop will continue
# https://tldp.org/LDP/Bash-Beginners-Guide/html/sect_09_03.html
# https://linuxize.com/post/bash-until-loop/
# TODO Is the loop really needed?
until assign_role;
do
  echo "Retrying role assignment..."
  sleep 1
done

echo "Role assignment successful"

identity_id="$(
  az identity show                       \
    --name "${resource_group}-identity"  \
    --resource-group "${resource_group}" \
    --output tsv --query "[id]"
  )"

storage_name=`echo $vm_name$RANDOM | tr -cd '[a-z0-9]'`

az storage account create -n $storage_name \
  --resource-group "${resource_group}" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false

# boot vm
az vm create                           \
  --name "${vm_name}"                  \
  --resource-group "${resource_group}" \
  --assign-identity "${identity_id}"   \
  --size "${vm_size_d}"                \
  --os-disk-size-gb "${os_size_d}"     \
  --public-ip-sku Standard             \
  --public-ip-address-dns-name "${vm_name}" \
  --image "${img_id}"                  \
  --admin-username "${USER}"           \
  --location "${location_d}"           \
  --boot-diagnostics-storage $storage_name \
  --storage-sku "Premium_LRS"          \
  --generate-ssh-keys
  # This only works if `ssh-agent` is running
  # --ssh-key-values "$(ssh-add -L)"
  # TODO Add key options to script

