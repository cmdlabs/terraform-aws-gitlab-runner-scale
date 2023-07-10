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
    instance_type               = "t3.micro"
    job_policy                  = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudfront:CreateInvalidation",
                "cloudfront:GetInvalidation",
                "cloudfront:ListInvalidations"
            ],
            "Resource": "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"
        }
    ]
}
EOF
    max_size                    = 1
    min_size                    = 0
    spot_price                  = "0.0100"
    subnet_ids                  = data.aws_subnets.selected.ids

  }

  gitlab = {
    uri                                = "https://gitlab.com/"
    api_token_ssm_path                 = "/gitlab/api_token"
    runner_registration_token_ssm_path = "/gitlab/runner_registration_token"
    runner_agents_per_instance         = 1
    narrow_to_membership               = "true"
    log_level                          = "debug"
  }

  lambda = {
    memory_size = 128
    rate        = "rate(1 minute)"
    runtime     = "python3.9"
  }
}
