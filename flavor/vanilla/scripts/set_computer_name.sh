#!/bin/sh

MAJOR_VERSION=$(sw_vers -productVersion | awk -F "." '{print $2}')
BUILD_VERSION=$(sw_vers -buildVersion)

COMPUTER_NAME="macOS 10${MAJOR_VERSION}-${BUILD_VERSION} VM"
LOCAL_HOST_NAME="macos10${MAJOR_VERSION}-${BUILD_VERSION}-vm"

scutil --set ComputerName "${COMPUTER_NAME}"
scutil --set LocalHostName "${LOCAL_HOST_NAME}"
