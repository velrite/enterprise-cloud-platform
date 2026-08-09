# Reads the network folder's own state directly — always current, no copy-paste IDs
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "ecp-terraform-state-681117450689"
    key    = "network/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_caller_identity" "current" {}
