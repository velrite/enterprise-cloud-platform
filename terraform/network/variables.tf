variable "project_name" {
  default = "enterprise-cloud-platform"
}

variable "region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "azs" {
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "cluster_name" {
  default = "ecp-cluster"
}
