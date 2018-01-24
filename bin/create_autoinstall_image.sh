#!/bin/sh -e

INSTALLER_APP="$1"
OUTPUT_PATH="$2"

#####

log_info() {
  echo "   \033[0;32m-- $*\033[0m" 1>&2
}

log_error() {
  echo "   \033[0;31m-- $*\033[0m" 1>&2
}

bail() {
  log_error "$@"
  exit 1
}

if [ $(id -u) -ne 0 -o -z "$SUDO_USER" ]; then
  bail "Script must be run as root with sudo."
fi

VMWARE_FUSION_APP="$(osascript -e 'POSIX path of (path to application "VMware Fusion")')"

if [ -z "$VMWARE_FUSION_APP" -o ! -e "$VMWARE_FUSION_APP" ]; then
  bail "VMware Fusion not found."
fi

if [ -z "$INSTALLER_APP" -o ! -e "$INSTALLER_APP" ]; then
  bail "Installer app not found."
fi

if [ -z "$OUTPUT_PATH" ]; then
  bail "No output path specified."
fi

#####

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
SUPPORT_DIR="$SCRIPT_DIR/../support/autoinstall_image"
INSTALLER_SUPPORT_DIR="$SUPPORT_DIR/installer"
PACKAGE_SUPPORT_DIR="$SUPPORT_DIR/package"
BOX_SUPPORT_DIR="$SUPPORT_DIR/box"
VAGRANT_SUPPORT_DIR="$SUPPORT_DIR/vagrant"

TEMP_DIR="$(/usr/bin/mktemp -d -t create_macos_autoinstall_box)"
SUDO_USER_TEMP_DIR="$(sudo -u $SUDO_USER /usr/bin/mktemp -d -t create_macos_autoinstall_box)"

MACOS_AUTOINSTALL_IMAGE="$TEMP_DIR/macos-autoinstall.dmg"

INSTALLESD_IMAGE="$INSTALLER_APP/Contents/SharedSupport/InstallESD.dmg"
INSTALLESD_MOUNTPOINT="$TEMP_DIR/installesd_mountpoint"
INSTALLESD_PACKAGES_DIR="$INSTALLESD_MOUNTPOINT/Packages"

BASESYSTEM_IMAGE="$INSTALLESD_MOUNTPOINT/BaseSystem.dmg"
BASESYSTEM_MOUNTPOINT="$TEMP_DIR/basesystem_mountpoint"
BASESYSTEM_PACKAGES_DIR="$BASESYSTEM_MOUNTPOINT/System/Installation/Packages"
BASESYSTEM_RC_CDROM_LOCAL="$BASESYSTEM_MOUNTPOINT/private/etc/rc.cdrom.local"

BASESYSTEM_RW_IMAGE="$TEMP_DIR/BaseSystem.dmg"

SYSTEMVERSION_PLIST="$BASESYSTEM_MOUNTPOINT/System/Library/CoreServices/SystemVersion.plist"

CUSTOMIZATION_PACKAGE_DIR="$TEMP_DIR/customization"
CUSTOMIZATION_PACKAGE="$TEMP_DIR/VagrantSupport.pkg"

CUSTOMIZATION_COMPONENT_PACKAGE_ROOT_DIR="$CUSTOMIZATION_PACKAGE_DIR/Root"
CUSTOMIZATION_COMPONENT_PACKAGE_SCRIPTS_DIR="$CUSTOMIZATION_PACKAGE_DIR/Scripts"
CUSTOMIZATION_COMPONENT_PACKAGE="$CUSTOMIZATION_PACKAGE_DIR/VagrantSupport.pkg"

USER_NAME="vagrant"

VMWARE_TOOLS_IMAGE="$VMWARE_FUSION_APP/Contents/Library/isoimages/darwin.iso"
VMWARE_TOOLS_MOUNTPOINT="$TEMP_DIR/vmware_tools_mountpoint"
VMWARE_TOOLS_PACKAGE="$VMWARE_TOOLS_MOUNTPOINT/Install VMware Tools.app/Contents/Resources/VMware Tools.pkg"
VMWARE_TOOLS_PACKAGE_DIR="$TEMP_DIR/vmware_tools_package"
VMWARE_VDISKMANAGER="$VMWARE_FUSION_APP/Contents/Library/vmware-vdiskmanager"

#####

if [ ! -e "$INSTALLESD_IMAGE" ]; then
  bail "File not found: $INSTALLESD_IMAGE"
fi

mkdir "$INSTALLESD_MOUNTPOINT"
mkdir "$BASESYSTEM_MOUNTPOINT"
mkdir "$VMWARE_TOOLS_MOUNTPOINT"

cleanup() {
  trap - EXIT INT TERM
  hdiutil detach -quiet -force "$VMWARE_TOOLS_MOUNTPOINT" > /dev/null 2>&1 || true
  hdiutil detach -quiet -force "$BASESYSTEM_MOUNTPOINT" > /dev/null 2>&1 || true
  hdiutil detach -quiet -force "$INSTALLESD_MOUNTPOINT" > /dev/null 2>&1 || true
  rm -rf "$TEMP_DIR" > /dev/null 2>&1 || true
  rm -rf "$SUDO_USER_TEMP_DIR" > /dev/null 2>&1 || true
  [[ $SIG == EXIT ]] || kill -$SIG $$ || true
}

for sig in EXIT INT TERM; do
  trap "SIG=$sig; cleanup;" $sig
done

#####

log_info "Attaching InstallESD image..."

hdiutil attach "$INSTALLESD_IMAGE" -mountpoint "$INSTALLESD_MOUNTPOINT" -nobrowse -owners on

#####

log_info "Attaching BaseSystem image..."

if [ ! -e "$BASESYSTEM_IMAGE" ]; then
  bail "File not found: $BASESYSTEM_IMAGE"
fi

hdiutil attach "$BASESYSTEM_IMAGE" -mountpoint "$BASESYSTEM_MOUNTPOINT" -nobrowse -owners on

#####

log_info "Checking macOS version..."

PRODUCTVERSION=$(/usr/libexec/PlistBuddy -c 'Print :ProductVersion' "$SYSTEMVERSION_PLIST")
PRODUCTBUILDVERSION=$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$SYSTEMVERSION_PLIST")

PRODUCTVERSION_MAJOR=$(echo $PRODUCTVERSION | awk -F "." '{print $2}')
PRODUCTVERSION_MINOR=$(echo $PRODUCTVERSION | awk -F "." '{print $3}')

#####

log_info "Found macOS version 10.$PRODUCTVERSION_MAJOR.$PRODUCTVERSION_MINOR, build $PRODUCTBUILDVERSION"

if [ $PRODUCTVERSION_MAJOR -lt 10 ]; then
  bail "The version of macOS detected is not new enough, this script requires 10.10 or later!"
fi

if [ $PRODUCTVERSION_MAJOR -eq 12 -a $PRODUCTVERSION_MINOR -gt 3 ] || [ $PRODUCTVERSION_MAJOR -gt 12 ]; then
  bail "The version of macOS detected is too new, this script requires 10.12.3 or earlier!"
fi

#####

log_info "Creating a new read-write image and restoring the BaseSystem image to it..."

hdiutil detach "$BASESYSTEM_MOUNTPOINT"

hdiutil create -o "$BASESYSTEM_RW_IMAGE" -size 10g -layout SPUD -fs HFS+J
hdiutil attach "$BASESYSTEM_RW_IMAGE" -mountpoint "$BASESYSTEM_MOUNTPOINT" -nobrowse -owners on

asr restore --source "$BASESYSTEM_IMAGE" --target "$BASESYSTEM_MOUNTPOINT" --noprompt --noverify --erase

diskutil umount "/Volumes/OS X Base System"

hdiutil attach "$BASESYSTEM_RW_IMAGE" -mountpoint "$BASESYSTEM_MOUNTPOINT" -nobrowse -owners on

#####

log_info "Copying the Packages from the InstallESD image to the new BaseSystem image..."

rm "$BASESYSTEM_PACKAGES_DIR"
ditto "$INSTALLESD_PACKAGES_DIR" "$BASESYSTEM_PACKAGES_DIR"

#####

log_info "Copying the original BaseSystem image and chunklist to the new BaseSystem image..."

cp "$INSTALLESD_MOUNTPOINT/BaseSystem.dmg" "$BASESYSTEM_MOUNTPOINT/"
cp "$INSTALLESD_MOUNTPOINT/BaseSystem.chunklist" "$BASESYSTEM_MOUNTPOINT/"

#####

log_info "Creating the package that will customize the installed OS for use with Vagrant..."

mkdir "$CUSTOMIZATION_PACKAGE_DIR"

cp -R "$PACKAGE_SUPPORT_DIR/" "$CUSTOMIZATION_PACKAGE_DIR/"

chmod 0550 "$CUSTOMIZATION_COMPONENT_PACKAGE_ROOT_DIR/private/etc/sudoers.d"
chmod 0440 "$CUSTOMIZATION_COMPONENT_PACKAGE_ROOT_DIR/private/etc/sudoers.d/vagrant"

chmod 0755 "$CUSTOMIZATION_COMPONENT_PACKAGE_ROOT_DIR/private/etc/rc.installer_cleanup"
chmod 0755 "$CUSTOMIZATION_COMPONENT_PACKAGE_ROOT_DIR/private/etc/rc.vagrant"

chmod a+x "$CUSTOMIZATION_COMPONENT_PACKAGE_SCRIPTS_DIR/postinstall"

hdiutil attach "$VMWARE_TOOLS_IMAGE" -mountpoint "$VMWARE_TOOLS_MOUNTPOINT" -nobrowse
pkgutil --expand "$VMWARE_TOOLS_PACKAGE" "$VMWARE_TOOLS_PACKAGE_DIR"
ditto -x -z "$VMWARE_TOOLS_PACKAGE_DIR/files.pkg/Payload" "$CUSTOMIZATION_COMPONENT_PACKAGE_ROOT_DIR"

pkgbuild --quiet \
  --root "$CUSTOMIZATION_COMPONENT_PACKAGE_ROOT_DIR" \
  --scripts "$CUSTOMIZATION_COMPONENT_PACKAGE_SCRIPTS_DIR" \
  --identifier Customization \
  --version 0.1 \
  "$CUSTOMIZATION_COMPONENT_PACKAGE"
productbuild \
  --package "$CUSTOMIZATION_COMPONENT_PACKAGE" \
  "$CUSTOMIZATION_PACKAGE"

cp "$CUSTOMIZATION_PACKAGE" "$BASESYSTEM_PACKAGES_DIR/"

#####

log_info "Configuring installer to run automatically and install custom packages..."

cp -R "$INSTALLER_SUPPORT_DIR/" "$BASESYSTEM_MOUNTPOINT/"

chmod a+x "$BASESYSTEM_RC_CDROM_LOCAL"

#####

log_info "Detaching the new BaseSystem image..."

hdiutil detach "$BASESYSTEM_MOUNTPOINT"

#####

log_info "Detaching the InstallESD image..."

hdiutil detach "$INSTALLESD_MOUNTPOINT"

#####

log_info "Converting the new BaseSystem to CD-ROM format..."

hdiutil convert -format UDZO -o "$MACOS_AUTOINSTALL_IMAGE" "$BASESYSTEM_RW_IMAGE"

if [ -n "$SUDO_UID" ] && [ -n "$SUDO_GID" ]; then
  chown $SUDO_UID:$SUDO_GID "$MACOS_AUTOINSTALL_IMAGE"
fi

mv "$MACOS_AUTOINSTALL_IMAGE" "$OUTPUT_PATH"

exit 0
