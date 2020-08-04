data "aws_ami" "amazonlinux2" {
 most_recent = true

 filter {
   name   = "owner-alias"
   values = ["amazon"]
 }

 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }

 owners = ["amazon"] # Canonical
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_ssm_parameter" "runner_registration_token" {
  name = var.gitlab.runner_registration_token_ssm_path
}
