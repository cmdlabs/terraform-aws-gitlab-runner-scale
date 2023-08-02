module "gitlab-runner" {
  source = "../../"

  asg = {
    associate_public_ip_address = true
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
    root_block_device           = {}
    spot_price                  = "0.0100"
    ssh_access = {
      source_cidr = ""
      key_name    = null
    }
    subnet_ids = ["subnet-xxx", "subnet-xxx", "subnet-xxx"]
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
