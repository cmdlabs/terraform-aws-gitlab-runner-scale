data "aws_ami" "amazonlinux2" {

  count = var.asg.image_id == "" ? 1 : 0

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  most_recent = true
  owners      = ["amazon"] # Canonical
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Assumes all of the subnets are in the same VPC hence we only need to take the first
data "aws_subnet" "current" {
  id = var.asg.subnet_ids[0]
}
