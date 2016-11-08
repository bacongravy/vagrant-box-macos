#!/bin/sh -e

shopt -s nullglob

install_dmg() {
    DMG="$1"
    echo "Installing from $DMG..."
    MOUNTPOINT=$(/usr/bin/mktemp -d -t install_packages)
    hdiutil attach "$DMG" -mountpoint "$MOUNTPOINT" -nobrowse -quiet
    for APP in "$MOUNTPOINT"/*.app; do
        APP_NAME="$(basename "$APP")"
        echo "Installing application $APP_NAME..."
        rm -rf "/Applications/$APP_NAME"
        ditto "$APP" "/Applications/$APP_NAME"
    done
    for PKG in "$MOUNTPOINT"/*.pkg; do
      PKG_NAME="$(basename "$PKG")"
      echo "Installing package $PKG_NAME..."
      installer -target / -pkg "$PKG"
    done
    hdiutil detach -quiet -force "$MOUNTPOINT"
    rm -rf "$MOUNTPOINT"
}

PACKAGES_DIR="/tmp/packages"
PACKAGE_DMGS="$PACKAGES_DIR"/*.dmg

for PACKAGE_DMG in $PACKAGE_DMGS; do
    install_dmg "$PACKAGE_DMG"
done

rm -rf "$PACKAGES_DIR"
