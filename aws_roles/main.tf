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
  alias                   = "bastion"
  profile                 = var.profile_bastion
  region                  = var.region
  shared_credentials_file = var.shared_credentials_file
}

provider "aws" {
  alias                   = "clusters"
  profile                 = var.profile_clusters
  region                  = var.region
  shared_credentials_file = var.shared_credentials_file
}

data "aws_caller_identity" "bastion" {
  provider = aws.bastion
}

data "aws_caller_identity" "clusters" {
  provider = aws.clusters
}

# STEP 2

data "aws_iam_policy_document" "clusters" {
  provider = aws.clusters
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      identifiers = [join(":", [
        "arn:aws:iam:",
        data.aws_caller_identity.clusters.account_id,
        join("/",[
          "oidc-provider",
          var.oidc_provider
        ])
      ])]
      type        = "Federated"
    }
    condition {
      test     = "StringEquals"
      variable = join(":", [
        var.oidc_provider,
        "sub"
      ])
      values = [
        join(":", [
          "system:serviceaccount",
          var.namespace,
          var.service_account
        ])
      ]
    }
  }
}

resource "aws_iam_role" "clusters" {
  assume_role_policy = data.aws_iam_policy_document.clusters.json
  name               = join("-", [
    var.namespace,
    "role"
  ])
  provider = aws.clusters
  tags = {
    Infrastructure = var.identifier
  }
}

# STEP 5

data "aws_iam_policy_document" "bastion" {
  provider = aws.bastion
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = [aws_iam_role.clusters.arn]
      type        = "AWS"
    }
  }
}

resource "aws_iam_role" "bastion" {
  assume_role_policy = data.aws_iam_policy_document.bastion.json
  name               = join("-", [
    var.namespace,
    "t-role"
  ])
  provider = aws.bastion
  tags = {
    Infrastructure = var.identifier
  }
}
