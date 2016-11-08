#!/bin/sh

touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
XCODE_COMMAND_LINE_TOOLS_UPDATE=$(softwareupdate -l | grep "\*.*Command Line" | tail -n 1 | awk -F"*" '{print $2}' | sed -e 's/^ *//' | tr -d '\n')
softwareupdate -i "$XCODE_COMMAND_LINE_TOOLS_UPDATE" --verbose
rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
