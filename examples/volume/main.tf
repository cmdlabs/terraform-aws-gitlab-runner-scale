resource "tls_private_key" "key" {
  algorithm = "ED25519"
}

resource "local_file" "key" {
  content  = tls_private_key.key.private_key_openssh
  filename = "key.pem"
}

resource "aws_key_pair" "key" {
  key_name   = "myterrakey"
  public_key = trimspace(tls_private_key.key.public_key_openssh)
}

module "gitlab-runner" {
  source = "../../"

  asg = {
    associate_public_ip_address = true
    instance_type               = "t3.large"
    job_policy                  = ""
    max_size                    = 5
    min_size                    = 1
    root_block_device = {
      encrypted             = true
      delete_on_termination = true
      volume_type           = "gp3"
      volume_size           = 40
    }
    spot_price = "0.0100"
    ssh_access = {
      source_cidr = "0.0.0.0/0"
      key_name    = aws_key_pair.key.key_name
    }
    subnet_ids = ["subnet-xxx", "subnet-xxx", "subnet-xxx"]
  }

  gitlab = {
    uri                                = "https://gitlab.com/"
    api_token_ssm_path                 = "/gitlab/api_token"
    runner_registration_token_ssm_path = "/gitlab/runner_registration_token"
    runner_agents_per_instance         = 1
    narrow_to_membership               = "true"
    log_level                          = "info"
  }

  lambda = {
    memory_size = 128
    rate        = "rate(5 minutes)"
    runtime     = "python3.8"
  }
}
