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

data "aws_subnet" "this" {
  cidr_block = var.subnet_cidr_block
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_security_group" "this" {
  name = "${var.identifier}-bastion"
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-bastion"
  }
  vpc_id = data.aws_vpc.this.id
}

resource "aws_security_group_rule" "ingress_icmp" {
  cidr_blocks = [
    var.vpc_cidr_block,
    var.vpc_secondary_cidr_block
  ]
  from_port         = -1
  protocol          = "icmp"
  security_group_id = aws_security_group.this.id
  to_port           = -1
  type              = "ingress"
}

resource "aws_security_group_rule" "ingress_ssh" {
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  to_port           = 22
  type              = "ingress"
}

resource "aws_security_group_rule" "egress" {
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.this.id
  to_port           = 0
  type              = "egress"
}

resource "aws_instance" "this" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = var.key_name
  subnet_id     = data.aws_subnet.this.id
  vpc_security_group_ids = [
    aws_security_group.this.id
  ]
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-bastion"
  }
}
