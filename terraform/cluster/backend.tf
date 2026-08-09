terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "ecp-terraform-state-681117450689"
    key            = "cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ecp-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}
