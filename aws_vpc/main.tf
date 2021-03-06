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

locals {
  private_subnet_ids = [for subnet in values(aws_subnet.private) : subnet.id]
  public_subnet_ids  = [for subnet in values(aws_subnet.public) : subnet.id]
  subnet_ids         = concat(local.private_subnet_ids, local.public_subnet_ids)
}

data "aws_organizations_organization" "this" {}

# VPC

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Infrastructure = var.identifier
    Name           = var.identifier
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  vpc_id     = aws_vpc.this.id
  cidr_block = var.vpc_secondary_cidr_block
}

# SUBNETS

resource "aws_subnet" "cluster" {
  for_each             = var.cluster_subnet
  availability_zone_id = each.value["availability_zone_id"]
  cidr_block           = each.value["cidr_block"]
  tags = {
    Infrastructure  = var.identifier
    Name            = "${var.identifier}-cluster-${each.key}"
    Tier            = "private"
  }
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "private" {
  for_each             = var.private_subnet
  availability_zone_id = each.value["availability_zone_id"]
  cidr_block           = each.value["cidr_block"]
  tags = {
    Infrastructure                    = var.identifier
    Name                              = "${var.identifier}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
    Tier                              = "private"
  }
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "public" {
  for_each                = var.public_subnet
  availability_zone_id    = each.value["availability_zone_id"]
  cidr_block              = each.value["cidr_block"]
  map_public_ip_on_launch = true
  tags = {
    Infrastructure           = var.identifier
    Name                     = "${var.identifier}-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
    Tier                     = "public"
  }
  vpc_id = aws_vpc.this.id
}

# GATEWAYS

resource "aws_internet_gateway" "this" {
  tags = {
    Infrastructure = var.identifier
    Name           = var.identifier
  }
  vpc_id = aws_vpc.this.id
}

resource "aws_eip" "this" {
  for_each   = var.public_subnet
  depends_on = [aws_internet_gateway.this]
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-${each.key}"
  }
  vpc = true
}

resource "aws_nat_gateway" "this" {
  for_each      = var.public_subnet
  allocation_id = aws_eip.this[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-${each.key}"
  }
}

# ROUTE TABLES

resource "aws_route_table" "private" {
  for_each = var.private_subnet
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.key].id
  }
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-private-${each.key}"
  }
  vpc_id = aws_vpc.this.id
}

resource "aws_route_table" "public" {
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}-public"
  }
  vpc_id = aws_vpc.this.id
}

resource "aws_route_table_association" "private" {
  for_each = var.private_subnet
  route_table_id = aws_route_table.private[each.key].id
  subnet_id      = aws_subnet.private[each.key].id
}

resource "aws_route_table_association" "public" {
  for_each = var.public_subnet
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[each.key].id
}

# NETWORK ACL

resource "aws_network_acl" "this" {
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  subnet_ids = local.subnet_ids
  tags = {
    Infrastructure = var.identifier
    Name           = "${var.identifier}"
  }
  vpc_id = aws_vpc.this.id
}

# RESOURCE ACCESS MANAGER

resource "aws_ram_resource_share" "this" {
  allow_external_principals = false
  name                      = "subnets"
  tags = {
    Infrastructure = var.identifier
  }
}

resource "aws_ram_principal_association" "this" {
  principal          = data.aws_organizations_organization.this.arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_resource_association" "cluster" {
  for_each           = var.cluster_subnet
  resource_arn       = aws_subnet.cluster[each.key].arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_resource_association" "private" {
  for_each           = var.cluster_subnet
  resource_arn       = aws_subnet.private[each.key].arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

resource "aws_ram_resource_association" "public" {
  for_each           = var.cluster_subnet
  resource_arn       = aws_subnet.public[each.key].arn
  resource_share_arn = aws_ram_resource_share.this.arn
}
