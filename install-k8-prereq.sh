#!/bin/sh
 
# Install Docker
curl -sSL get.docker.com | sh && \
sudo usermod pi -aG docker
 
# Disable Swap
sudo dphys-swapfile swapoff && \
sudo dphys-swapfile uninstall && \
sudo update-rc.d dphys-swapfile remove
sudo systemctl disable dphys-swapfile
 
echo Adding " cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1" to /boot/cmdline.txt
sudo cp /boot/cmdline.txt /boot/cmdline_backup.txt
orig="$(head -n1 /boot/cmdline.txt) cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1"
echo $orig | sudo tee /boot/cmdline.txt
 
# https://github.com/kubernetes/kubernetes/issues/71305#issuecomment-479558920
# Change iptables to legacy mode
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
 
# Add repo list and install kubeadm
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
sudo apt-get update -q && \
sudo apt-get install -qy kubeadm
