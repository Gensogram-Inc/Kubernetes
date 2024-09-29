#!/bin/bash

# Update the package list and install required packages
sudo apt-get update -y
sudo apt-get install -y curl unzip apt-transport-https ca-certificates software-properties-common

# Install AWS CLI
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# Install kubectl
echo "Installing kubectl..."
sudo curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client --output=yaml

# Install eksctl (for creating and managing EKS clusters)
echo "Installing eksctl..."
curl -LO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
tar -xzf eksctl_Linux_amd64.tar.gz
sudo mv eksctl /usr/local/bin
eksctl version

# Configure AWS CLI (this requires AWS access and secret keys)
# Replace YOUR_ACCESS_KEY and YOUR_SECRET_KEY with actual keys, or set them interactively.
echo "Configuring AWS CLI..."
aws configure set aws_access_key_id YOUR_ACCESS_KEY
aws configure set aws_secret_access_key YOUR_SECRET_KEY
aws configure set default.region us-east-1  # Set your preferred region
aws configure set default.output json

# Confirm AWS CLI is working
aws sts get-caller-identity

# Set up eksctl and create an EKS cluster (optional, can be commented out if you prefer to run manually)
#eksctl create cluster --name my-eks-cluster --version 1.30 --region us-east-1 --nodegroup-name linux-nodes --node-type t2.medium --nodes 2 --nodes-min 1 --nodes-max 4 --managed

echo "EKS setup complete. You can now use kubectl and eksctl to manage your EKS clusters."

