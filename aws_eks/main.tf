terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.1.3"
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "this" {
  cidr_block = var.vpc_cidr_block
}

data "aws_subnet" "cluster_0" {
  cidr_block = var.subnet_cluster_0_cidr_block
}

data "aws_subnet" "cluster_1" {
  cidr_block = var.subnet_cluster_1_cidr_block
}

data "aws_subnet" "private_0" {
  cidr_block = var.subnet_private_0_cidr_block
}

data "aws_subnet" "private_1" {
  cidr_block = var.subnet_private_1_cidr_block
}

# ROLES

resource "aws_iam_role" "eks_cluster" {
  assume_role_policy = <<EOF
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
EOF
  name = "${var.identifier}-eksClusterRole"
  tags = {
    Infrastructure = var.identifier
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.id
}

resource "aws_iam_role" "node_instance" {
  assume_role_policy = <<EOF
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
EOF
  name = "${var.identifier}-NodeInstanceRole"
  tags = {
    Infrastructure = var.identifier
  }
}

resource "aws_iam_role_policy_attachment" "node_instance_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_instance.id
}

resource "aws_iam_role_policy_attachment" "node_instance_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_instance.id
}

resource "aws_iam_role_policy_attachment" "node_instance_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_instance.id
}

# SECURITY GROUPS

resource "aws_security_group" "cluster_security_group" {
  name = "${var.identifier}-ClusterSecurityGroup"
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-ClusterSecurityGroup"
  }
  vpc_id = data.aws_vpc.this.id
}

resource "aws_security_group_rule" "cluster_security_group_ingress" {
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.cluster_security_group.id
  source_security_group_id = aws_security_group.cluster_security_group.id 
  to_port                  = 0
  type                     = "ingress"
}

resource "aws_security_group_rule" "cluster_security_group_egress" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.cluster_security_group.id
  to_port           = 0
  type              = "egress"
}

resource "aws_security_group" "node_remote_access" {
  name   = "${var.identifier}-NodeRemoteAccess"
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-NodeRemoteAccess"
  }
  vpc_id = data.aws_vpc.this.id
}

resource "aws_security_group_rule" "node_remote_access_ingress" {
  cidr_blocks = [
    var.vpc_cidr_block,
    var.vpc_secondary_cidr_block
  ]
  from_port                = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node_remote_access.id
  to_port                  = 22
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_remote_access_egress" {
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.node_remote_access.id
  to_port           = 0
  type              = "egress"
}

resource "aws_security_group" "node_private" {
  name   = "${var.identifier}-NodePrivate"
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-NodePrivate"
  }
  vpc_id = data.aws_vpc.this.id
}

resource "aws_security_group_rule" "node_private_icmp" {
  cidr_blocks = [
    var.vpc_cidr_block,
    var.vpc_secondary_cidr_block
  ]
  from_port         = -1
  protocol          = "icmp"
  security_group_id = aws_security_group.node_private.id
  to_port           = -1
  type              = "ingress"
}

# LAUNCH TEMPLATE

resource "aws_launch_template" "this" {
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      delete_on_termination = true
      volume_size           = 20
      volume_type           = "gp2"
    }
  }
  key_name      = var.key_name
  name          = var.identifier
  network_interfaces {
    device_index = 0
    security_groups = [
      aws_security_group.cluster_security_group.id,
      aws_security_group.node_remote_access.id,
      aws_security_group.node_private.id
    ]
  }
  tags = {
    "eks:cluster-name"   = var.identifier
    "eks:nodegroup-name" = var.identifier
    Infrastructure       = var.identifier
  }
}

# CLUSTER RESOURCES

resource "aws_eks_cluster" "this" {
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster
  ]
  kubernetes_network_config {
    service_ipv4_cidr = var.services_cidr_block
  }
  name     = var.identifier
  role_arn = aws_iam_role.eks_cluster.arn
  tags = {
    Infrastructure = var.identifier
  }
  vpc_config {
    security_group_ids = [
      aws_security_group.cluster_security_group.id
    ]
    subnet_ids = [ 
      data.aws_subnet.cluster_0.id,
      data.aws_subnet.cluster_1.id
    ]
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name = aws_eks_cluster.this.name
  depends_on = [
    aws_iam_role_policy_attachment.node_instance_worker,
    aws_iam_role_policy_attachment.node_instance_cni,
    aws_iam_role_policy_attachment.node_instance_registry
  ]
  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }
  node_group_name = var.identifier
  node_role_arn   = aws_iam_role.node_instance.arn
  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }
  subnet_ids = [ 
      data.aws_subnet.private_0.id,
      data.aws_subnet.private_1.id
  ]
  tags = {
    Infrastructure = var.identifier
  }
}
