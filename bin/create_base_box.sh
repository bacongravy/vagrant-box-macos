#!/bin/sh -e

IMAGE_PATH="$1"
OUTPUT_PATH="$2"
OUTPUT_NAME="$3"

BOX_DISK_SIZE="64GB"

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

VMWARE_FUSION_APP="$(osascript -e 'POSIX path of (path to application "VMware Fusion")')"

if [ -z "$VMWARE_FUSION_APP" -o ! -e "$VMWARE_FUSION_APP" ]; then
  bail "VMware Fusion not found."
fi

if [ -z "$IMAGE_PATH" -o ! -e "$IMAGE_PATH" ]; then
  bail "Could not find autoinstall image ($IMAGE_PATH)"
fi

IMAGE_NAME="$(basename "$IMAGE_PATH" .dmg)"

if [ -z "$OUTPUT_PATH" ]; then
  bail "No output path specified."
fi

if [ -z "$OUTPUT_NAME" ]; then
  bail "No output name specified."
fi

######

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
SUPPORT_DIR="$SCRIPT_DIR/../support/base_box"
INSTALLER_SUPPORT_DIR="$SUPPORT_DIR/installer"
PACKAGE_SUPPORT_DIR="$SUPPORT_DIR/package"
BOX_SUPPORT_DIR="$SUPPORT_DIR/box"
VM_SUPPORT_DIR="$SUPPORT_DIR/vm"

TEMP_DIR="$(/usr/bin/mktemp -d -t create_macos_basebox)"

VMWARE_VDISKMANAGER="$VMWARE_FUSION_APP/Contents/Library/vmware-vdiskmanager"

MACOS_AUTOINSTALL_BOX_DIR="$TEMP_DIR/macos-autoinstall-box"
MACOS_AUTOINSTALL_BOX="$TEMP_DIR/macos-autoinstall.box"

MACOS_AUTOINSTALL_VM_DIR="$TEMP_DIR/macos-autoinstall-vm"
MACOS_AUTOINSTALL_VM_CDROM="$MACOS_AUTOINSTALL_VM_DIR/cdrom.dmg"
MACOS_AUTOINSTALL_VM_DISK="$MACOS_AUTOINSTALL_VM_DIR/disk.vmdk"

MACOS_BOX_DIR="$TEMP_DIR/box"
MACOS_BOX_DISK="$MACOS_BOX_DIR/disk.vmdk"
MACOS_BOX="$TEMP_DIR/$IMAGE_NAME.box"

#####

cleanup() {
  trap - EXIT INT TERM
  vagrant box remove --force macos-autoinstall > /dev/null 2>&1 || true
  VAGRANT_CWD="$MACOS_AUTOINSTALL_VM_DIR" vagrant destroy --force > /dev/null 2>&1 || true
  rm -rf "$TEMP_DIR" > /dev/null 2>&1 || true
  [[ $SIG == EXIT ]] || kill -$SIG $$ || true
}

for sig in EXIT INT TERM; do
  trap "SIG=$sig; cleanup;" $sig
done

#####

log_info "Creating and adding macos-autoinstall box..."

mkdir "$MACOS_AUTOINSTALL_BOX_DIR"
cp -R "$BOX_SUPPORT_DIR/autoinstall/" "$MACOS_AUTOINSTALL_BOX_DIR"
pushd "$MACOS_AUTOINSTALL_BOX_DIR"
tar czf "$MACOS_AUTOINSTALL_BOX" ./*
popd

vagrant box add "$MACOS_AUTOINSTALL_BOX" --name macos-autoinstall --force

#####

log_info "Booting macos-autoinstall box..."

mkdir "$MACOS_AUTOINSTALL_VM_DIR"
cp -R "$VM_SUPPORT_DIR/autoinstall/" "$MACOS_AUTOINSTALL_VM_DIR"
ln -s "$(cd "$(dirname "$IMAGE_PATH")"; pwd)/$(basename "$IMAGE_PATH")" "$MACOS_AUTOINSTALL_VM_CDROM"
"$VMWARE_VDISKMANAGER" -c -s "$BOX_DISK_SIZE" -a lsilogic -t 0 "$MACOS_AUTOINSTALL_VM_DISK"

pushd "$MACOS_AUTOINSTALL_VM_DIR"
vagrant up
vagrant halt
popd

log_info "Creating base box..."

cp -R "$BOX_SUPPORT_DIR/base/" "$MACOS_BOX_DIR"
mv "$MACOS_AUTOINSTALL_VM_DISK" "$MACOS_BOX_DISK"
"$VMWARE_VDISKMANAGER" -d "$MACOS_BOX_DISK"
"$VMWARE_VDISKMANAGER" -k "$MACOS_BOX_DISK"
pushd "$MACOS_BOX_DIR"
tar czf "$MACOS_BOX" ./*
popd

mv "$MACOS_BOX" "$OUTPUT_PATH"
log_info "Base box created. Run 'vagrant box add $OUTPUT_PATH --name $OUTPUT_NAME' to add the box."

exit 0
