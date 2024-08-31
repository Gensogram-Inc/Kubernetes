#Configure Kernel Modules

sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF


sudo modprobe overlay
sudo modprobe br_netfilter

#Configure Sysctl Parameters

sudo tee /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

#RUN a command to apply this immediately:
sudo sysctl --system


#For containerd:

sudo apt install -y containerd
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

#Set up a containerd configuration file:

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

sudo systemctl restart containerd

#Add Kubernetes Repository

sudo swapoff -a
sudo apt update && sudo apt-get upgrade -y
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
sudo apt install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

#Install Kubernetes Components

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl


