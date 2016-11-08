#!/bin/sh

defaults write com.apple.screensaver askForPassword -bool false
defaults write com.apple.screensaver idleTime -integer 0

defaults write -g KeyRepeat -int 0
defaults write -g InitialKeyRepeat -int 10
defaults write -g ApplePressAndHoldEnabled -bool false

defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
