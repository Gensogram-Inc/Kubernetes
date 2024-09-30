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

# Install eksctl
echo "Installing eksctl..."
curl -LO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
tar -xzf eksctl_Linux_amd64.tar.gz
sudo mv eksctl /usr/local/bin
eksctl version

# Configure AWS CLI
echo "Configuring AWS CLI..."
aws configure set aws_access_key_id YOUR_ACCESS_ID
aws configure set aws_secret_access_key YOUR_SECRET_KEY
aws configure set default.region us-east-1
aws configure set default.output json

# Check if roles already exist
EXISTING_CLUSTER_ROLE=$(aws iam get-role --role-name EKSClusterRole 2>/dev/null)
EXISTING_WORKER_ROLE=$(aws iam get-role --role-name EKSWorkerNodeRole 2>/dev/null)

# Step 1: Create IAM Role for EKS Cluster (Skip if already exists)
if [[ -z "$EXISTING_CLUSTER_ROLE" ]]; then
  echo "Creating IAM role for EKS Cluster..."

  # Create trust-policy.json file
  echo "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Principal\": {
          \"Service\": \"eks.amazonaws.com\"
        },
        \"Action\": \"sts:AssumeRole\"
      }
    ]
  }" > trust-policy.json

  # Create the IAM role and attach policies
  aws iam create-role --role-name EKSClusterRole --assume-role-policy-document file://trust-policy.json
  aws iam attach-role-policy --role-name EKSClusterRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
  aws iam attach-role-policy --role-name EKSClusterRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy
else
  echo "EKS Cluster Role already exists, skipping creation."
fi

# Step 2: Create IAM Role for EKS Worker Nodes (Skip if already exists)
if [[ -z "$EXISTING_WORKER_ROLE" ]]; then
  echo "Creating IAM role for EKS Worker Nodes..."

  # Create worker-node-trust-policy.json file
  echo "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Principal\": {
          \"Service\": \"ec2.amazonaws.com\"
        },
        \"Action\": \"sts:AssumeRole\"
      }
    ]
  }" > worker-node-trust-policy.json

  # Create the IAM role and attach policies
  aws iam create-role --role-name EKSWorkerNodeRole --assume-role-policy-document file://worker-node-trust-policy.json
  aws iam attach-role-policy --role-name EKSWorkerNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
  aws iam attach-role-policy --role-name EKSWorkerNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
  aws iam attach-role-policy --role-name EKSWorkerNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
else
  echo "EKS Worker Node Role already exists, skipping creation."
fi

# Step 3: Create the EKS Cluster
echo "Creating EKS cluster ger-eks-cluster..."
eksctl create cluster --name ogens-cluster --version 1.30 --region us-east-1 --nodegroup-name linux-nodes --node-type t2.medium --nodes 2 --nodes-min 1 --nodes-max 4 --managed

# Step 4: Associate OIDC Provider for the Cluster
echo "Associating OIDC provider for the EKS cluster..."
eksctl utils associate-iam-oidc-provider --region us-east-1 --cluster ogens-cluster --approve

# Step 5: Map IAM User gensogram to Kubernetes Access
echo "Mapping IAM user gensogram to Kubernetes user in aws-auth ConfigMap..."
cat > aws-auth-map.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    # Add roles here as needed
  mapUsers: |
    - userarn: arn:aws:iam::783359668727:user/gensogram  # IAM user gensogram
      username: gensogram   # Mapped Kubernetes user
      groups:
        - system:masters    # This grants admin privileges
EOF

kubectl apply -f aws-auth-map.yaml

# Step 6: Create Role and RoleBinding for gensogram to Access Kubernetes Resources
echo "Creating Role for full access to all resources..."
cat > eks-console-access-role.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: eks-console-access-role
  namespace: kube-system
rules:
# Core resources (Pods, PodTemplates, Services, Nodes)
- apiGroups: [""]
  resources:
    - pods
    - podtemplates
    - services
    - nodes
  verbs: ["get", "list", "watch", "create", "delete", "update"]

# Apps resources (ReplicaSets, Deployments, StatefulSets, DaemonSets)
- apiGroups: ["apps"]
  resources:
    - replicasets
    - deployments
    - statefulsets
    - daemonsets
  verbs: ["get", "list", "watch", "create", "delete", "update"]

# Batch resources (Jobs, CronJobs)
- apiGroups: ["batch"]
  resources:
    - jobs
    - cronjobs
  verbs: ["get", "list", "watch", "create", "delete", "update"]

# Autoscaling resources (HorizontalPodAutoscalers)
- apiGroups: ["autoscaling"]
  resources:
    - horizontalpodautoscalers
  verbs: ["get", "list", "watch", "create", "delete", "update"]

# Scheduling resources (PriorityClasses)
- apiGroups: ["scheduling.k8s.io"]
  resources:
    - priorityclasses
  verbs: ["get", "list", "watch", "create", "delete", "update"]
EOF


kubectl apply -f eks-console-access-role.yaml

echo "Creating RoleBinding for gensogram to access Kubernetes resources..."
cat > eks-console-access-rolebinding.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: eks-console-access-rolebinding
  namespace: kube-system
subjects:
- kind: User
  name: gensogram                         # Kubernetes username mapped from the IAM user gensogram
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: eks-console-access-role
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f eks-console-access-rolebinding.yaml

# Step 7: Create ClusterRoleBinding for gensogram user to access cluster resources
echo "Creating ClusterRoleBinding for gensogram..."
cat > gensogram-clusterrolebinding.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gensogram-admin-binding
subjects:
- kind: User
  name: gensogram
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

# Apply the ClusterRoleBinding
kubectl apply -f gensogram-clusterrolebinding.yaml

# Step 8: Add Required IAM Permissions for EKS Console Access
echo "Attaching required IAM policies to your user or role..."

# Attach read-only policy to EKSServicePolicy (if needed)
aws iam attach-user-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy --user-name gensogram
aws iam attach-user-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --user-name gensogram

# Ensure IAM user gensogram has permissions to see Kubernetes workloads
aws iam attach-user-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --user-name gensogram

echo "EKS setup complete. The IAM user gensogram is mapped, and permissions are applied."
