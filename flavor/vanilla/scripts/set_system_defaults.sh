#!/bin/sh

defaults write /Library/Preferences/com.apple.windowserver.plist DisplayResolutionEnabled -bool true
defaults write /Library/Preferences/com.apple.screensaver.plist loginWindowIdleTime -integer 0

pmset -b sleep 0
