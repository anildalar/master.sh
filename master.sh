#!/bin/bash

# Ensure the script runs as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Cleanup Kubernetes installation if any previous setup exists
echo "Cleaning up previous Kubernetes setup..."
hostnamectl set-hostname master-node-1
kubeadm reset -f
apt-get purge kubeadm kubelet kubectl -y
apt-get autoremove -y
apt-get purge containerd -y
apt-get autoremove -y

# Remove Kubernetes and containerd configuration files and directories
echo "Removing Kubernetes and containerd configuration files..."
rm -rf /etc/cni /opt/cni /etc/cni/net.d /var/lib/kubelet /etc/kubernetes

# Reset iptables and IPVS tables (if applicable)
echo "Resetting iptables and IPVS tables..."
iptables --flush
iptables -t nat --flush
iptables -t mangle --flush
iptables -X

# If using IPVS, clean IPVS tables
if command -v ipvsadm > /dev/null 2>&1; then
  ipvsadm --clear
fi

# Update and prepare the system
echo "Updating and upgrading system packages..."
apt update -y && apt upgrade -y

# Disable swap
echo "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Install required packages for Kubernetes installation
echo "Installing necessary packages for Kubernetes..."
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Remove the existing Kubernetes GPG key if it exists to avoid prompts
echo "Removing existing Kubernetes GPG key (if it exists)..."
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository and GPG key
echo "Adding Kubernetes repository..."
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Update package list and install Kubernetes components
echo "Installing Kubernetes components..."
apt-get update -y
apt-get install -y kubelet kubeadm kubectl --allow-change-held-packages
apt-mark hold kubelet kubeadm kubectl

# Install containerd
echo "Installing containerd..."
apt install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
systemctl status containerd --no-pager

# Verify the installed versions
echo "Verifying installed versions..."
kubelet --version
kubeadm version
kubectl version --client

# Configure Kubernetes networking and IP forwarding
echo "Configuring Kubernetes networking..."
echo -e "br_netfilter" | tee /etc/modules-load.d/k8s.conf && modprobe br_netfilter
echo -e "net.bridge.bridge-nf-call-ip6tables = 1\nnet.bridge.bridge-nf-call-iptables = 1" | tee /etc/sysctl.d/k8s.conf
echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/99-kubernetes-ip-forward.conf
sysctl --system

# Initialize the Kubernetes master node
echo "Initializing Kubernetes master node..."
kubeadm init --pod-network-cidr=192.168.0.0/16

# Configure kubectl for the master node
echo "Configuring kubectl..."
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://reweave.azurewebsites.net/k8s/v1.32/net.yaml

# Get the status of nodes
echo "Getting the status of nodes..."
kubectl get nodes --kubeconfig=$HOME/.kube/config

kubectl apply -f https://reweave.azurewebsites.net/k8s/v1.32/net.yaml
