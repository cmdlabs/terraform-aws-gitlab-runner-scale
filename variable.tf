variable "vpc_id" {
  type = string
}

variable "ssh_access" {
  type = object({
    source_cidr = string
    key_name    = string
  })
}

variable "associate_public_ip_address" {
  type    = bool
  default = false
}

variable "gitlab" {
  type = object({
    uri                                = string
    api_token_ssm_path                 = string
    runner_agents_per_instance         = number
    runner_registration_token_ssm_path = string
    narrow_to_membership               = string
    log_level                          = string
  })
}

variable "asg" {
  type = object({
    subnet_ids       = list(string)
    min_size         = number
    max_size         = number
    desired_capacity = number
  })
}

variable "lambda_runtime" {
  type    = string
  default = "python3.8"
}
