provider "aws" {
  region = "ap-northeast-2"
}

data "aws_vpc" "my_vpc" { 
  tags = {
    Name = "test-vpc" 
  }
}
data "aws_subnet" "my_pub_2a" {
  tags = {
    Name = "test-pub-2a"
  }
}
data "aws_subnet" "my_pub_2c" {
  tags = {
    Name = "test-pub-2c"
  }
}
data "aws_subnet" "my_pvt_2a" {
  tags = {
    Name = "test-pvt-2a"
  }
}
data "aws_subnet" "my_pvt_2c" {
  tags = {
    Name = "test-pvt-2c"
  }
}

data "aws_security_group" "my_sg_web" {
  name   = "test-sg-web"
}

resource "aws_iam_role" "eks_cluster_iam_role" { # aws_iam_role.eks_cluster_iam_role.name
  name = "eks-cluster-iam-role"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_iam_role.name
}

resource "aws_eks_cluster" "my_eks_cluster" {
  name     = "eks-cluster"
  role_arn =  aws_iam_role.eks_cluster_iam_role.arn 
  version = "1.33"
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  vpc_config {
    security_group_ids = [data.aws_security_group.my_sg_web.id]         
    subnet_ids         = concat(data.aws_subnet.my_pvt_2a[*].id, data.aws_subnet.my_pvt_2c[*].id)
    endpoint_private_access = true
    endpoint_public_access = false
   }
}

resource "aws_iam_role" "eks_node_iam_role" { # aws_iam_role.eks_node_iam_role.name
  name = "eks-node-iam-role"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_iam_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_iam_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_iam_role.name
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.my_eks_cluster.name
  node_group_name = "worker-node-group"
  node_role_arn   = aws_iam_role.eks_node_iam_role.arn
  subnet_ids      = concat(data.aws_subnet.my_pvt_2a[*].id, data.aws_subnet.my_pvt_2c[*].id)
  instance_types = ["t2.micro"]
  capacity_type  = "ON_DEMAND"
  remote_access {
    ec2_ssh_key               = "test-key"
  }
  labels = {
    "role" = "eks_node_iam_role"
  }
  scaling_config {
    desired_size = 10
    min_size     = 10
    max_size     = 20
    }
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}

# CoreDNS 애드온
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.my_eks_cluster.name
  addon_name   = "coredns"
  depends_on = [aws_eks_node_group.eks_node_group]
}

# kube-proxy 애드온
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.my_eks_cluster.name
  addon_name   = "kube-proxy"
  depends_on = [aws_eks_node_group.eks_node_group]
}

# VPC CNI 애드온
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.my_eks_cluster.name
  addon_name   = "vpc-cni"
  depends_on = [aws_eks_node_group.eks_node_group]
}

# EBS CSI 애드온
#resource "aws_eks_addon" "aws_ebs_csi_driver" {
#  cluster_name = aws_eks_cluster.my_eks_cluster.name
#  addon_name   = "aws-ebs-csi-driver"
#  depends_on = [aws_eks_node_group.eks_node_group]
#}
