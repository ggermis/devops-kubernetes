# -*- mode: ruby -*-
# # vi: set ft=ruby :

require 'yaml'
require 'fileutils'

Vagrant.require_version ">= 1.6.0"

CLOUD_CONFIG_PATH = File.join(File.dirname(__FILE__), ENV['USER_DATA'] || 'user-data')
CONFIG = File.join(File.dirname(__FILE__), "config.rb")

# Defaults for config options defined in CONFIG
$num_instances = 1
$num_masters = 1
$num_workers = 2
$master_name_prefix = "master"
$worker_name_prefix = "worker"
$update_channel = "beta"
$image_version = "current"
$enable_serial_logging = false
$share_home = false
$vm_gui = false
$vm_memory = 1024
$vm_cpus = 1
$shared_folders = {}
$forwarded_ports = {}

# Attempt to apply the deprecated environment variable NUM_INSTANCES to
# $num_instances while allowing config.rb to override it
if ENV["NUM_INSTANCES"].to_i > 0 && ENV["NUM_INSTANCES"]
  $num_instances = ENV["NUM_INSTANCES"].to_i
end

if File.exist?(CONFIG)
  require CONFIG
end

# Use old vb_xxx config variables when set
def vm_gui
  $vb_gui.nil? ? $vm_gui : $vb_gui
end

def vm_memory
  $vb_memory.nil? ? $vm_memory : $vb_memory
end

def vm_cpus
  $vb_cpus.nil? ? $vm_cpus : $vb_cpus
end

def master_ip(n)
  "172.17.8.#{n+10}"
end

def worker_ip(n)
  "172.17.8.#{n+20}"
end

def master_cloud_config_file
  "user-data-master"
end

def worker_cloud_config_file
  "user-data-worker"
end


Vagrant.configure("2") do |config|
  # always use Vagrants insecure key
  config.ssh.insert_key = false

  config.vm.box = "coreos-%s" % $update_channel
  if $image_version != "current"
      config.vm.box_version = $image_version
  end
  config.vm.box_url = "http://%s.release.core-os.net/amd64-usr/%s/coreos_production_vagrant.json" % [$update_channel, $image_version]

  ["vmware_fusion", "vmware_workstation"].each do |vmware|
    config.vm.provider vmware do |v, override|
      override.vm.box_url = "http://%s.release.core-os.net/amd64-usr/%s/coreos_production_vagrant_vmware_fusion.json" % [$update_channel, $image_version]
    end
  end

  config.vm.provider :virtualbox do |v|
    # On VirtualBox, we don't have guest additions or a functional vboxsf
    # in CoreOS, so tell Vagrant that so it can be smarter.
    v.check_guest_additions = false
    v.functional_vboxsf     = false
  end

  # plugin conflict
  if Vagrant.has_plugin?("vagrant-vbguest") then
    config.vbguest.auto_update = false
  end

  # Master nodes
  (1..$num_masters).each do |i|
    config.vm.define vm_name = "%s-%02d" % [$master_name_prefix, i] do |config|
      config.vm.hostname = vm_name

      if $enable_serial_logging
        logdir = File.join(File.dirname(__FILE__), "log")
        FileUtils.mkdir_p(logdir)

        serialFile = File.join(logdir, "%s-serial.txt" % vm_name)
        FileUtils.touch(serialFile)

        ["vmware_fusion", "vmware_workstation"].each do |vmware|
          config.vm.provider vmware do |v, override|
            v.vmx["serial0.present"] = "TRUE"
            v.vmx["serial0.fileType"] = "file"
            v.vmx["serial0.fileName"] = serialFile
            v.vmx["serial0.tryNoRxLoss"] = "FALSE"
          end
        end

        config.vm.provider :virtualbox do |vb, override|
          vb.customize ["modifyvm", :id, "--uart1", "0x3F8", "4"]
          vb.customize ["modifyvm", :id, "--uartmode1", serialFile]
        end
      end

      if $expose_docker_tcp
        config.vm.network "forwarded_port", guest: 2375, host: ($expose_docker_tcp + i - 1), auto_correct: true
      end

      $forwarded_ports.each do |guest, host|
        config.vm.network "forwarded_port", guest: guest, host: host, auto_correct: true
      end

      ["vmware_fusion", "vmware_workstation"].each do |vmware|
        config.vm.provider vmware do |v|
          v.gui = vm_gui
          v.vmx['memsize'] = vm_memory
          v.vmx['numvcpus'] = vm_cpus
        end
      end

      config.vm.provider :virtualbox do |vb|
        vb.name = vm_name
        vb.gui = vm_gui
        vb.memory = vm_memory
        vb.cpus = vm_cpus
      end

      ip = master_ip(i)
      config.vm.network :private_network, ip: ip

      # Uncomment below to enable NFS for sharing the host machine into the coreos-vagrant VM.
      #config.vm.synced_folder ".", "/home/core/share", id: "core", :nfs => true, :mount_options => ['nolock,vers=3,udp']
      $shared_folders.each_with_index do |(host_folder, guest_folder), index|
        config.vm.synced_folder host_folder.to_s, guest_folder.to_s, id: "core-share%02d" % index, nfs: true, mount_options: ['nolock,vers=3,udp']
      end

      if $share_home
        config.vm.synced_folder ENV['HOME'], ENV['HOME'], id: "home", :nfs => true, :mount_options => ['nolock,vers=3,udp']
      end

      if File.exist?(master_cloud_config_file)
        config.vm.provision :file, :source => "#{master_cloud_config_file}", :destination => "/tmp/vagrantfile-user-data"
        config.vm.provision :shell, :inline => "mv /tmp/vagrantfile-user-data /var/lib/coreos-vagrant/", :privileged => true

        config.vm.provision :file, :source => "certificates/ca.pem", :destination => "/tmp/ca.pem"
        config.vm.provision :file, :source => "certificates/apiserver.pem", :destination => "/tmp/apiserver.pem"
        config.vm.provision :file, :source => "certificates/apiserver-key.pem", :destination => "/tmp/apiserver-key.pem"
        config.vm.provision :shell, :inline => "mkdir -p /etc/kubernetes/ssl && mv /tmp/*.pem /etc/kubernetes/ssl/", :privileged => true
        config.vm.provision :shell, :inline => "chown -R root:root /etc/kubernetes/ssl", :privileged => true
        config.vm.provision :shell, :inline => "chmod 0600 /etc/kubernetes/ssl/*-key.pem", :privileged => true
      end

    end
  end

  # Worker nodes
  (1..$num_workers).each do |i|
    config.vm.define vm_name = "%s-%02d" % [$worker_name_prefix, i] do |config|
      config.vm.hostname = vm_name

      if $enable_serial_logging
        logdir = File.join(File.dirname(__FILE__), "log")
        FileUtils.mkdir_p(logdir)

        serialFile = File.join(logdir, "%s-serial.txt" % vm_name)
        FileUtils.touch(serialFile)

        ["vmware_fusion", "vmware_workstation"].each do |vmware|
          config.vm.provider vmware do |v, override|
            v.vmx["serial0.present"] = "TRUE"
            v.vmx["serial0.fileType"] = "file"
            v.vmx["serial0.fileName"] = serialFile
            v.vmx["serial0.tryNoRxLoss"] = "FALSE"
          end
        end

        config.vm.provider :virtualbox do |vb, override|
          vb.customize ["modifyvm", :id, "--uart1", "0x3F8", "4"]
          vb.customize ["modifyvm", :id, "--uartmode1", serialFile]
        end
      end

      if $expose_docker_tcp
        config.vm.network "forwarded_port", guest: 2375, host: ($expose_docker_tcp + i - 1), auto_correct: true
      end

      $forwarded_ports.each do |guest, host|
        config.vm.network "forwarded_port", guest: guest, host: host, auto_correct: true
      end

      ["vmware_fusion", "vmware_workstation"].each do |vmware|
        config.vm.provider vmware do |v|
          v.gui = vm_gui
          v.vmx['memsize'] = vm_memory
          v.vmx['numvcpus'] = vm_cpus
        end
      end

      config.vm.provider :virtualbox do |vb|
        vb.name = vm_name
        vb.gui = vm_gui
        vb.memory = vm_memory
        vb.cpus = vm_cpus
      end

      ip = worker_ip(i)
      config.vm.network :private_network, ip: ip

      # Uncomment below to enable NFS for sharing the host machine into the coreos-vagrant VM.
      #config.vm.synced_folder ".", "/home/core/share", id: "core", :nfs => true, :mount_options => ['nolock,vers=3,udp']
      $shared_folders.each_with_index do |(host_folder, guest_folder), index|
        config.vm.synced_folder host_folder.to_s, guest_folder.to_s, id: "core-share%02d" % index, nfs: true, mount_options: ['nolock,vers=3,udp']
      end

      if $share_home
        config.vm.synced_folder ENV['HOME'], ENV['HOME'], id: "home", :nfs => true, :mount_options => ['nolock,vers=3,udp']
      end

      if File.exist?(worker_cloud_config_file)
        config.vm.provision :file, :source => "#{worker_cloud_config_file}", :destination => "/tmp/vagrantfile-user-data"
        config.vm.provision :shell, :inline => "mv /tmp/vagrantfile-user-data /var/lib/coreos-vagrant/", :privileged => true

        config.vm.provision :file, :source => "certificates/ca.pem", :destination => "/tmp/ca.pem"
        config.vm.provision :file, :source => "certificates/#{vm_name}-worker.pem", :destination => "/tmp/worker.pem"
        config.vm.provision :file, :source => "certificates/#{vm_name}-worker-key.pem", :destination => "/tmp/worker-key.pem"
        config.vm.provision :shell, :inline => "mkdir -p /etc/kubernetes/ssl && mv /tmp/*.pem /etc/kubernetes/ssl/", :privileged => true
        config.vm.provision :shell, :inline => "chown -R root:root /etc/kubernetes/ssl", :privileged => true
        config.vm.provision :shell, :inline => "chmod 0600 /etc/kubernetes/ssl/*-key.pem", :privileged => true
      end

    end
  end
end
