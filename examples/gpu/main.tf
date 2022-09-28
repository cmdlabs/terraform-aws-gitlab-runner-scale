data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

module "gitlab-runner" {
  source = "../../"

  asg = {
    associate_public_ip_address = false
    desired_capacity            = 1
    instance_type               = "p3.2xlarge"
    max_size                    = 1
    min_size                    = 0
    subnet_ids                  = data.aws_subnets.selected.ids
  }

  gitlab = {
    uri                                = "https://gitlab.com/"
    api_token_ssm_path                 = "/gitlab/api_token"
    narrow_to_membership               = "true"
    runner_agents_per_instance         = 1
    runner_job_tags                    = "gpu"
    runner_registration_token_ssm_path = "/gitlab/runner_registration_token"
    log_level                          = "debug"
  }

  lambda = {
    memory_size = 128
    rate        = "rate(1 minute)"
    runtime     = "python3.8"
  }
}
