#!/bin/sh -e

INSTALLER_APP="$1"

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

if [ -z "$INSTALLER_APP" -o ! -e "$INSTALLER_APP" ]; then
  bail "Installer app not found."
fi

#####

TEMP_DIR="$(/usr/bin/mktemp -d -t get_installer_version)"

INSTALLESD_IMAGE="$INSTALLER_APP/Contents/SharedSupport/InstallESD.dmg"
INSTALLESD_MOUNTPOINT="$TEMP_DIR/installesd_mountpoint"

BASESYSTEM_IMAGE="$INSTALLESD_MOUNTPOINT/BaseSystem.dmg"
BASESYSTEM_MOUNTPOINT="$TEMP_DIR/basesystem_mountpoint"

SYSTEMVERSION_PLIST="$BASESYSTEM_MOUNTPOINT/System/Library/CoreServices/SystemVersion.plist"

#####

if [ ! -e "$INSTALLESD_IMAGE" ]; then
  bail "File not found: $INSTALLESD_IMAGE"
fi

mkdir "$INSTALLESD_MOUNTPOINT"
mkdir "$BASESYSTEM_MOUNTPOINT"

cleanup() {
  trap - EXIT INT TERM
  hdiutil detach -quiet -force "$BASESYSTEM_MOUNTPOINT" > /dev/null 2>&1 || true
  hdiutil detach -quiet -force "$INSTALLESD_MOUNTPOINT" > /dev/null 2>&1 || true
  rm -rf "$TEMP_DIR" > /dev/null 2>&1 || true
  [[ $SIG == EXIT ]] || kill -$SIG $$ || true
}

for sig in EXIT INT TERM; do
  trap "SIG=$sig; cleanup;" $sig
done

#####

log_info "Attaching InstallESD image..."

hdiutil attach "$INSTALLESD_IMAGE" -mountpoint "$INSTALLESD_MOUNTPOINT" -nobrowse -owners on > /dev/null 2>&1

#####

if [ ! -e "$BASESYSTEM_IMAGE" ]; then
  bail "File not found: $BASESYSTEM_IMAGE"
fi

log_info "Attaching BaseSystem image..."

hdiutil attach "$BASESYSTEM_IMAGE" -mountpoint "$BASESYSTEM_MOUNTPOINT" -nobrowse -owners on > /dev/null 2>&1

#####

PRODUCTVERSION=$(/usr/libexec/PlistBuddy -c 'Print :ProductVersion' "$SYSTEMVERSION_PLIST")
PRODUCTBUILDVERSION=$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$SYSTEMVERSION_PLIST")

PRODUCTVERSION_MAJOR=$(echo $PRODUCTVERSION | awk -F "." '{print $2}')

#####

echo "10$PRODUCTVERSION_MAJOR-$PRODUCTBUILDVERSION"

exit 0
