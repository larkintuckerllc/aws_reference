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

data "aws_caller_identity" "this" {}

data "aws_iam_policy_document" "cluster_account" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      identifiers = [join(":", [
        "arn:aws:iam:",
        data.aws_caller_identity.this.account_id,
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

resource "aws_iam_role" "cluster_account" {
  assume_role_policy = data.aws_iam_policy_document.cluster_account.json
  name               = join("-", [
    var.namespace,
    "role"
  ])
  tags = {
    Infrastructure = var.identifier
  }
}
