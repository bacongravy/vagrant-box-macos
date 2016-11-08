# vagrant-box-macos

Scripts for building Vagrant boxes for VMware Fusion that boot macOS.

* `bin/create_autoinstall_image.sh`: builds an autoinstall image from a macOS installer app
* `bin/create_base_box.sh`: builds a base box from an autoinstall image
* `bin/create_flavor_box.sh`: provisions a flavor box from the base box

These scripts can be chained together by using the `vagrant-box-macos.rb` wrapper script, building a provisioned box from a macOS installer app in one step.

These scripts support building boxes with OS X 10.10 Yosemite, OS X 10.11 El Capitan, and macOS 10.12 Sierra guest operating systems.

## System Requirements

* macOS 10.12 Sierra host operating system (may also work with 10.10 and 10.11)
* At least 8 GB RAM (16 GB recommended)
* At least 2 cores (4 recommended)
* At least 30 GB of available disk space

## Dependencies

The following software is required. Versions other than those mentioned may work, but have not been tested:

* VMware Fusion 8.5.1
* Vagrant 1.8.6
* Vagrant VMware Fusion Plugin 4.0.14

[Get VMware Fusion](http://www.vmware.com/products/fusion.html)
//
[Get Vagrant](https://www.vagrantup.com/)
//
[Get Vagrant VMware Fusion Plugin](https://www.vagrantup.com/vmware/)

## Basic Usage

Run with no arguments, the `vagrant-box-macos.rb` script will find the latest installed installer app, create a base box from it, and then add the box to Vagrant:

    $ sudo ./vagrant-box-macos.rb

This script also supports provisioning different "flavors" of boxes; for instance, you can create a box provisioned with basic developer tools, starting from an installer app, by passing the `vanilla` flavor name as an option:

    $ sudo ./vagrant-box-macos.rb --flavor-name vanilla

The `vagrant-box-macos.rb` script is just a wrapper around the other scripts included in this project. Using those other scripts directly, you can accomplish something similar to what the above invocation of the wrapper script does, like this:

    $ sudo bin/create_autoinstall_image.sh "/Applications/Install macOS Sierra.app" dmg/macos1012.dmg
    $ bin/create_base_box.sh dmg/macos1012.dmg box/macos1012.box macos1012
    $ vagrant add box box/macos1012.box --name macos1012
    $ bin/create_flavor_box.sh macos1012 vanilla box/macos1012-vanilla.box macos1012-vanilla
    $ vagrant box add box/macos1012-vanilla.box --name macos1012-vanilla

## Details

### vagrant-box-macos.rb

The `vagrant-box-macos.rb` script is a convenience wrapper around the rest of the scripts in this project. It can be used to chain the scripts together, and will infer as many options as possible, including finding the latest installed installer app, generating a name for the autoinstall image based on the version of the installer app OS, generating a name for the base box based on the autoinstall image name, and generating a name for the flavor box based on the base box name and the flavor name. All of these defaults can be overridden with command-line options, and the script will automatically skip some steps if the specified image or box already exists.

### bin/create_autoinstall_image.sh

The `bin/create_autoinstall_image.sh` script finds the latest version of the installer app in the /Applications folder and builds a boot disk image from it. When used as a boot disk, the image automatically installs an operating system on the first disk found, configures it with a `vagrant` user account, and installs the VMware Tools.

This script must be run with `sudo`.

### bin/create_base_box.sh

The `bin/create_base_box.sh` script uses an image created by the `create_autoinstall_image.sh` script to create a vagrant base box that boots macOS. The installed operating system is configured with the bare minimum required for Vagrant to function.

This script requires patience. The script my take 30 minutes, or longer, to complete. It is normal to see the message `default: Warning: Host appears down. Retrying...` printed repeatedly while the script runs.

### bin/create_flavor_box.sh

The `bin/create_flavor_box.sh` script provisions a base box with a flavor. Flavors are defined by Vagrantfiles that include provision directives. The flavor box is created by booting the base box using the flavor Vagrantfile and then repackaging the resulting machine.

## Flavors

### vanilla

The `vanilla` flavor provisions a minimal environment by installing the Xcode command-line tools and setting some useful defaults for running the operating system in a VM, including screensaver and power settings and the computer name. This flavor finishes provisioning by installing all available software updates.

### template

This flavor is meant to be copied and modified; it can then be used to run an arbitrary set of scripts, and to install packages and applications contained in local disk image files, in order to provision the flavor box. This flavor finishes provisioning by installing all available software updates.

## Acknowledgements

This project was inspired by the great work of others:

http://grahamgilbert.com/blog/2013/08/23/creating-an-os-x-base-box-for-vagrant-with-packer/
http://heavyindustries.io/blog/2015/07/05/create_osx_vagrant_vmware_box.html
https://spin.atomicobject.com/2015/11/17/vagrant-osx/
https://github.com/timsutton/osx-vm-templates
https://github.com/boxcutter/macos

## Why?

My preferred operating system is macOS, and ever since I started using Vagrant, I thought that it would be nice to have be able to boot a macOS box as easily as a Linux box. However, it wasn't until I was watching an episode of Mr. Robot that I was finally inspired to figure out how to make it happen. In the episode, Elliot is shown quickly booting what appeared to be a virtual machine running a Linux desktop environment in order to examine the contents of an untrusted CD-ROM, and I thought, "I want to be able to do that kind of thing with macOS!".

In researching prior art, I discovered Timothy Sutton's `osx-vm-templates` project and realized that I would be able to use those scripts and packer templates to accomplish my goal. However, after using those the scripts and templates a few times and trying to customize them, I found that they didn't always work reliably for me. I began trying to understand how they worked so that I could make them more reliable and customizable.

Once I learned enough about the scripts and templates to fix the reliability issues I found, and customize them the way I wanted, I realized that I wanted a solution that was easier to customize, and that didn't have a dependency on `packer`. I decided to create a set of scripts using only `vagrant` to provision and repackage virtual machines, and to make them easily customizable so that I could create many different flavors of box, each with different preferences and software pre-installed, and so that the scripts would be useful for other people to use, too.

I chose to support only VMware Fusion boxes because of the Vagrant VMware plugin support for linked clones and shared folders, and because in my experience I have found that macOS virtualizes better in VMware Fusion than the alternatives.
