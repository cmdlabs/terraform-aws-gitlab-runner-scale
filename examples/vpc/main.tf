module "vpc" {
  source = "github.com/cmdlabs/cmd-tf-aws-vpc?ref=0.12.0"

  vpc_name                  = "gitlab-runner-ci-test"
  vpc_cidr_block            = "10.0.0.0/16"
  availability_zones        = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
  enable_per_az_nat_gateway = false
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
            "Action": [
                "ec2:DescribeInstances",
                "ssm:*"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
EOF
    max_size                    = 1
    min_size                    = 0
    spot_price                  = "0.0100"
    ssh_access = {
      source_cidr = ""
      key_name    = null
    }
    subnet_ids = module.vpc.private_tier_subnet_ids
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
    runtime     = "python3.8"
  }
}
