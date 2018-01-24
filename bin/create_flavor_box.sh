#!/bin/sh -e

export BOX_NAME="$1"
export FLAVOR_DIR="$2"
OUTPUT_PATH="$3"
OUTPUT_NAME="$4"

#####

log_info() {
  echo "   \033[0;32m-- $*\033[0m" 1>&2
}

log_error() {
  echo "   \033[0;31m-- $*\033[0m" 1>&2
}

bail() {
  log_error "$1"
  exit 1
}

if [ $(id -u) -eq 0 -a -n "$SUDO_USER" ]; then
  bail "Script must be NOT be run as root with sudo."
fi

#####

if [ -z "$BOX_NAME" ]; then
  bail "Box name not specified."
fi

if [ -z "$FLAVOR_DIR" ]; then
  bail "Flavor not specified."
fi

if [ -z "$OUTPUT_PATH" ]; then
  bail "Output path not specified."
fi

if [ -z "$OUTPUT_NAME" ]; then
  bail "Output name not specified."
fi

if [ ! -e "$FLAVOR_DIR" ]; then
  bail "Flavor not found."
fi

FLAVOR_DIR="$(cd "$FLAVOR_DIR"; pwd)"

VMWARE_FUSION_APP="$(osascript -e 'POSIX path of (path to application "VMware Fusion")')"

if [ -z "$VMWARE_FUSION_APP" -o ! -e "$VMWARE_FUSION_APP" ]; then
  bail "VMware Fusion not found."
fi

VMWARE_VDISKMANAGER="$VMWARE_FUSION_APP/Contents/Library/vmware-vdiskmanager"

#####

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
TEMP_DIR=$(/usr/bin/mktemp -d -t create_flavor_box)
FLAVOR_PROJECT_DIR="$TEMP_DIR/flavor-project"
FLAVOR_BOX_DIR="$TEMP_DIR/flavor-box"
FLAVOR_BOX="$TEMP_DIR/flavor.box"

#####

cleanup() {
  trap - EXIT INT TERM
  VAGRANT_CWD="$FLAVOR_PROJECT_DIR" vagrant destroy --force > /dev/null 2>&1 || true
  rm -rf "$TEMP_DIR" > /dev/null 2>&1 || true
  [[ $SIG == EXIT ]] || kill -$SIG $$ || true
}

for sig in EXIT INT TERM; do
  trap "SIG=$sig; cleanup;" $sig
done

#####

log_info "Booting the base box and provisioning..."

mkdir "$FLAVOR_PROJECT_DIR"
cp "$FLAVOR_DIR/Vagrantfile" "$FLAVOR_PROJECT_DIR/"

pushd "$FLAVOR_PROJECT_DIR"

vagrant up
if [ -x "$FLAVOR_DIR/provision" ]; then
  "$FLAVOR_DIR/provision"
fi
vagrant halt

#####

log_info "Merging the provisioned disk with the base box to create the flavor box..."

mkdir "$FLAVOR_BOX_DIR"

alias js-eval="osascript -l JavaScript -e"

BASE_BOX_MACHINE_UUID=$(cat .vagrant/machines/default/vmware_fusion/index_uuid)
BASE_BOX_MACHINE_INDEX=$(cat ~/.vagrant.d/data/machine-index/index)
BASE_BOX_NAME=$(js-eval "JSON.parse('$BASE_BOX_MACHINE_INDEX').machines['$BASE_BOX_MACHINE_UUID'].extra_data.box.name")
BASE_BOX_VERSION=$(js-eval "JSON.parse('$BASE_BOX_MACHINE_INDEX').machines['$BASE_BOX_MACHINE_UUID'].extra_data.box.version")

BASE_BOX_VM_DIR=~/.vagrant.d/boxes/"$BASE_BOX_NAME"/"$BASE_BOX_VERSION"/vmware_fusion

cp "$BASE_BOX_VM_DIR/Vagrantfile" "$FLAVOR_BOX_DIR/"
cp "$BASE_BOX_VM_DIR/metadata.json" "$FLAVOR_BOX_DIR/"
sed 's/\(sata0:0\.file[nN]ame\) *= *"\(.*\)"/\1 = "disk.vmdk"/' "$BASE_BOX_VM_DIR/macos.vmx" > "$FLAVOR_BOX_DIR/macos.vmx"

BASE_BOX_MACHINE_DIR=$(dirname `cat .vagrant/machines/default/vmware_fusion/id`)
BASE_BOX_MACHINE_DISK_NAME="$(cat "$BASE_BOX_MACHINE_DIR/macos.vmx" | awk -F " ?= ?" 'tolower($0) ~ /sata0:0\.filename/ { gsub(/"/, "", $2); print $2 }')"

"$VMWARE_VDISKMANAGER" -t 0 -r "$BASE_BOX_MACHINE_DIR/$BASE_BOX_MACHINE_DISK_NAME" "$FLAVOR_BOX_DIR/disk.vmdk"

popd

#####

log_info "Packaging the flavor box..."

pushd "$FLAVOR_BOX_DIR"
tar czf "$FLAVOR_BOX" ./*
popd

mv "$FLAVOR_BOX" "$OUTPUT_PATH"
log_info "Flavor box created. Run 'vagrant box add $OUTPUT_PATH --name $OUTPUT_NAME' to add the box."

exit 0
