#!/bin/bash

# Cleanup Kubernetes installation if any previous setup exists
sudo hostname master-node-1
sudo kubeadm reset -f
sudo apt-get purge kubeadm kubelet kubectl -y
sudo apt-get autoremove -y
sudo apt-get purge containerd -y
sudo apt-get autoremove -y

# Remove Kubernetes and containerd configuration files and directories
sudo rm -rf /etc/cni
sudo rm -rf /opt/cni
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/kubelet
sudo rm -rf /etc/kubernetes

# Wait for system to reboot and then resume the installation (continue running the script after reboot)

# Update and upgrade system packages
sudo apt update -y && sudo apt upgrade -y

# Add Kubernetes apt repository and overwrite the existing keyring file without prompt
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Force overwrite of the existing keyring file
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Update apt packages again
sudo apt-get update -y

# Disable swap memory
sudo swapoff -a

# Disable swap on reboot
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

# Comment out swap line in /etc/fstab
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Install Kubernetes components
sudo apt install -y kubelet kubeadm kubectl

# Hold the Kubernetes components at the current version
sudo apt-mark hold kubelet kubeadm kubectl

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Make IP forwarding persistent across reboots
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Update apt packages one more time
sudo apt update -y

# Install containerd for container runtime
sudo apt install -y containerd

# Apply Flannel CNI plugin for Kubernetes networking
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Initialize Kubernetes master node
sudo kubeadm init

# Set up kubeconfig
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "Kubernetes setup completed."

