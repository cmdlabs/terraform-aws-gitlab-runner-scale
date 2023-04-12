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
    instance_type = "t3.micro"
    max_size      = 1
    spot_price    = "0.0100"
    subnet_ids    = data.aws_subnets.selected.ids
  }

  gitlab = {
    allowed_ip_range                   = "34.74.90.64/28,34.74.226.0/24" # GitLab webhook IP range https://docs.gitlab.com/ee/user/gitlab_com/
    api_token_ssm_path                 = "/gitlab/api_token"
    runner_registration_token_ssm_path = "/gitlab/runner_registration_token"
    uri                                = "https://gitlab.com/"
  }

  lambda = {
    allow_function_url = true
    cors = {
      allow_origins = ["https://gitlab.com"]
    }
  }
}

output "lambda_function_url" {
  description = "Public URL to be used by the GitLab webhook to trigger runner creation"
  value       = module.gitlab-runner.lambda_function_url
}
