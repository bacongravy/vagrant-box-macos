#!/usr/bin/env ruby

require 'optparse'

BIN_DIR = "#{File.dirname(__FILE__)}/bin"
DMG_DIR = "#{File.dirname(__FILE__)}/dmg"
BOX_DIR = "#{File.dirname(__FILE__)}/box"

def log_info(msg)
  STDERR.puts "\033[0;32m-- #{msg}\033[0m"
end

def log_error(msg)
  STDERR.puts "\033[0;31m-- #{msg}\033[0m"
end

def bail(msg)
  log_error msg
  exit 1
end

def run_command(cmd)
  system(cmd) || bail("Non-zero exit code: #{cmd}")
end

def box_added?(name)
  system(%Q( vagrant box list | cut -d" " -f1 | grep -q "^#{name}$" ))
  $?.exitstatus == 0
end

def image_specified?
  $options[:image_path]
end

def image_exists?
  $options[:image_path] && File.exists?($options[:image_path])
end

def base_box_exists?
  $options[:base_box_path] && File.exists?($options[:base_box_path])
end

def base_box_added?
  $options[:base_box_name] && box_added?($options[:base_box_name])
end

def flavor_specified?
  $options[:flavor_name]
end

def flavor_box_exists?
  $options[:flavor_box_path] && File.exists?($options[:flavor_box_path])
end

def flavor_box_added?
  $options[:flavor_box_name] && box_added?($options[:flavor_box_name])
end

$options = {}

OptionParser.new do |o|
  o.on('--installer-path PATH', 'Path to the input installer app.') { |path| $options[:installer_path] = path }
  o.on('--image-path PATH', 'Path to the input/output image.') { |path| $options[:image_path] = path }
  o.on('--base-box-name NAME', 'Name of the input/output box.') { |name| $options[:base_box_name] = name }
  o.on('--base-box-path PATH', 'Path to the input/output box.') { |path| $options[:base_box_path] = path }
  o.on('--flavor-name NAME', 'Name of the flavor.') { |name| $options[:flavor_name] = name }
  o.on('--flavor-box-name NAME', 'Name of output flavor box.') { |name| $options[:flavor_box_name] = name }
  o.on('--flavor-box-path PATH', 'Path to output flavor box.') { |path| $options[:flavor_box_path] = path }
  o.on('-h', '--help') { puts o; exit }
  o.parse!
end

$actions = {}

loop do
  if flavor_specified?
    break if flavor_box_added?
    $actions[:add_flavor_box] = true
    break if flavor_box_exists?
    $actions[:create_flavor_box] = true
  end
  break if base_box_added?
  $actions[:add_base_box] = true
  break if base_box_exists?
  $actions[:create_base_box] = true
  break if image_exists?
  $actions[:create_image] = true
  break if image_specified?
  $actions[:get_version] = true
  break
end

run_with_root_privileges = "sudo"
run_without_root_privileges = ""

if Process.uid == 0 && ENV["SUDO_USER"]
  run_with_root_privileges = ""
  run_without_root_privileges = "sudo -u \"#{ENV["SUDO_USER"]}\""
end

if $actions[:get_version] || $actions[:create_image]
  unless $options[:installer_path]
    installer_paths = ["/Applications/Install macOS Sierra.app", "/Applications/Install OS X El Capitan.app", "/Applications/Install OS X Yosemite.app"]
    while $options[:installer_path] = installer_paths.shift
      break if File.exists?($options[:installer_path])
    end
  end
  if !$options[:installer_path] || !File.exists?($options[:installer_path])
    bail "Installer app not found."
  end
end

if $actions[:create_base_box]
  if $options[:image_path]
    unless File.exists? $options[:image_path]
      bail "Image not found."
    end
    $options[:base_box_name] ||= File.basename($options[:image_path], ".dmg")
  end
end

if $options[:flavor_name]
  $options[:flavor_path] = "#{File.dirname(__FILE__)}/flavor/#{$options[:flavor_name]}"
  unless File.exists? $options[:flavor_path]
    bail "Flavor not found."
  end
end

if $actions[:get_version]
  log_info "Getting OS version from installer app..."
  installer_version = %x( #{run_with_root_privileges} "#{BIN_DIR}/get_installer_version.sh" "#{$options[:installer_path]}" ).chomp
  if installer_version.length == 0
    bail "Could not read the OS version from the installer app."
  end
  $options[:image_path] ||= "#{DMG_DIR}/macos#{installer_version}.dmg"
  $options[:base_box_name] ||= "macos#{installer_version}"
  log_info "Found OS version '#{installer_version}'."
end

if $actions[:create_image] || $actions[:create_base_box]
  bail("Image path not specified.") unless image_specified?
end

if $actions[:create_image]
  unless image_exists?
    log_info "Creating autoinstall image..."
    run_command(%Q( #{run_with_root_privileges} "#{BIN_DIR}/create_autoinstall_image.sh" "#{$options[:installer_path]}" "#{$options[:image_path]}" ))
    log_info "Created autoinstall image."
  end
end

if $actions[:create_base_box] || $actions[:create_flavor_box]
  bail("Base box name not specified.") if !$options[:base_box_name]
  $options[:base_box_path] ||= "#{BOX_DIR}/#{$options[:base_box_name]}.box"
end

if $actions[:create_base_box]
  unless base_box_exists?
    log_info "Creating base box..."
    run_command(%Q( #{run_without_root_privileges} "#{BIN_DIR}/create_base_box.sh" "#{$options[:image_path]}" "#{$options[:base_box_path]}" "#{$options[:base_box_name]}" ))
    log_info "Created base box."
  end
end

if $actions[:add_base_box]
  unless base_box_added?
    log_info "Adding base box..."
    run_command(%Q( #{run_without_root_privileges} vagrant box add "#{$options[:base_box_path]}" --name "#{$options[:base_box_name]}" ))
    log_info "Added base box."
  end
end

def generate_flavor_box_name(name, flavor)
  ((name.match(/-/) ? name.split('-')[0..-2] : [name] ) + [flavor]).join('-')
end

if $actions[:create_flavor_box]
  $options[:flavor_box_name] ||= generate_flavor_box_name($options[:base_box_name], $options[:flavor_name]) if $options[:base_box_name]
  bail("Flavor box name not specified.") if !$options[:flavor_box_name]
  $options[:flavor_box_path] ||= "#{BOX_DIR}/#{$options[:flavor_box_name]}.box"
  unless flavor_box_exists?
    log_info "Creating flavor box..."
    run_command(%Q( #{run_without_root_privileges} "#{BIN_DIR}/create_flavor_box.sh" "#{$options[:base_box_name]}" "#{$options[:flavor_path]}" "#{$options[:flavor_box_path]}" "#{$options[:flavor_box_name]}" ))
    log_info "Created flavor box."
  end
end

if $actions[:add_flavor_box]
  unless flavor_box_added?
    log_info "Adding flavor box..."
    run_command(%Q( #{run_without_root_privileges} vagrant box add "#{$options[:flavor_box_path]}" --name "#{$options[:flavor_box_name]}" ))
    log_info "Added flavor box."
  end
end
