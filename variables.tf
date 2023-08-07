variable "asg" {
  description = "Resource attributes required by the auto scale group configuration"
  type = object({
    associate_public_ip_address  = optional(bool, false)
    desired_capacity             = optional(number, 0)
    executor                     = optional(string, "docker")
    force_instance_deletion_time = optional(number, 600)
    image_id                     = optional(string, "")
    instance_type                = string
    job_policy                   = optional(any, "")
    managed_policy_arns          = optional(list(string), [])
    log_level                    = optional(string, "info")
    max_size                     = number
    min_size                     = optional(number, 0)
    root_block_device            = optional(any, {})
    scaling_warmup               = optional(number, 240)
    spot_price                   = optional(string, null)
    ssh_access = optional(object({
      source_cidr = optional(string, "")
      key_name    = optional(string, null)
    }), {})
    subnet_ids = list(string)
  })
  validation {
    condition     = var.asg.desired_capacity <= var.asg.max_size && var.asg.desired_capacity >= var.asg.min_size && var.asg.max_size >= var.asg.min_size
    error_message = "Desired capacity must be less or equal to max size and great or equal to min size. Max size msut also be greater or equal to min size."
  }
  validation {
    condition     = can(regex("^docker$|^shell$", var.asg.executor))
    error_message = "Valid values for var: asg.executor are ('docker', 'shell')."
  }
  validation {
    condition     = var.asg.force_instance_deletion_time >= 30 && var.asg.force_instance_deletion_time <= 7200 && floor(var.asg.force_instance_deletion_time) == var.asg.force_instance_deletion_time
    error_message = "Accepted timeout is between: 30-7200."
  }
  validation {
    condition     = can(regex("^ami-[a-z]+|^$", var.asg.image_id))
    error_message = "Image ami needs to be in the format ami-xxx or an empty string."
  }
  validation {
    condition     = can(jsonencode(var.asg.job_policy))
    error_message = "The job policy must be valid JSON."
  }
  validation {
    condition     = var.asg.spot_price == null || can(regex("^$|^\\d+(\\.\\d+)?$", var.asg.spot_price))
    error_message = "Valid values for var: asg.spot_price are ('null' (don't use spot pricing), '' (empty, use spot pricing but set no limit), or a numeric string value to set as a maximum spot price')."
  }
}

variable "gitlab" {
  description = "Resource attributes required by the lambda and EC2 to connect to gitlab"
  type = object({
    activity_since_hours               = optional(number, 4)
    allowed_ip_range                   = optional(string, "")
    api_token_ssm_path                 = string
    log_level                          = optional(string, "info")
    narrow_to_membership               = optional(string, "true")
    project_id                         = optional(string, "")
    runner_agents_per_instance         = optional(number, 1)
    runner_job_tags                    = optional(string, "")
    runner_registration_token_ssm_path = string
    runner_registration_type           = optional(string, "legacy")
    runner_idletime                    = optional(string, "30")
    runner_version                     = optional(string, "latest")
    uri                                = string
  })

  validation {
    condition     = var.gitlab.activity_since_hours >= 1 && floor(var.gitlab.activity_since_hours) == var.gitlab.activity_since_hours
    error_message = "Activity since hours must be greater than 1 and a whole number."
  }
  validation {
    condition     = (can(regex("^authentication-token-group-creation$", var.gitlab.runner_registration_type)) && length(var.gitlab.project_id) != 0) || (!can(regex("^authentication-token-group-creation$", var.gitlab.runner_registration_type)) && length(var.gitlab.project_id) >= 0)
    error_message = "You must have a value for gitlab.project_id if gitlab.runner_registration_type = 'authentication-token-group-creation'."
  }
  validation {
    condition     = var.gitlab.runner_agents_per_instance >= 1 && floor(var.gitlab.runner_agents_per_instance) == var.gitlab.runner_agents_per_instance
    error_message = "Runner agens per instance must be greater than 1 and a whole number."
  }
  validation {
    condition     = can(tonumber(var.gitlab.runner_idletime)) && tonumber(var.gitlab.runner_idletime) >= 1 && floor(tonumber(var.gitlab.runner_idletime)) == tonumber(var.gitlab.runner_idletime)
    error_message = "Runner idle time must be greater than 1 and a whole number string."
  }
  validation {
    condition     = can(regex("^legacy$|^authentication-token$|^authentication-token-group-creation$", var.gitlab.runner_registration_type))
    error_message = "Valid values for var: gitlab.runner_registration_type are ('legacy' - using a guest read api registration token, 'authentication token' - using the runner project token or 'authentication-token-group-creation' - using a project owner token). See https://docs.gitlab.com/runner/register/ for more information"
  }
}

variable "lambda" {
  description = "Resource attributes for the pending job lambda function. rate also has the special value of 'off' to turn off polling. This is not recomended and is better to use 'rate(1 hour)' to ensure instances are cleaned up"
  type = object({
    allow_function_url = optional(bool, false)
    cors = optional(object({
      allow_credentials = optional(bool, false)
      allow_headers     = optional(list(string), [])
      allow_methods     = optional(list(string), [])
      allow_origins     = list(string),
      expose_headers    = optional(list(string), [])
      max_age           = optional(number, 0)
      }), {
      allow_origins = []
    })
    memory_size = optional(number, 128)
    rate        = optional(string, "rate(1 minute)")
    runtime     = optional(string, "python3.11")
  })
  validation {
    condition     = can(regex("^cron|^rate|^off$", var.lambda.rate))
    error_message = "Valid values for var: lambda.rate are ('cron(...)', 'rate(...) or off')."
  }
  validation {
    condition     = can(regex("^cron|^off$", var.lambda.rate)) || (can(regex("^rate", var.lambda.rate)) && can(regex("1 minute\\)$|[^1] minutes\\)$|1 hour\\)$|[^1] hours\\)$|1 day\\)$|[^1] days\\)$", var.lambda.rate)))
    error_message = "Valid values for var: lambda.rate are ('rate(1 minute)', 'rate(x minutes)' 'rate(1 hour)', 'rate(x hours)' 'rate(1 day)' or 'rate(x days)'). ${var.lambda.rate}"
  }
}

variable "provisioner" {
  default     = "local"
  description = "Provisioner to use to create the lambda python dependencies; 'container' or 'local'"
  type        = string
  validation {
    condition     = can(regex("^container$|^local$", var.provisioner))
    error_message = "Valid values for var: provisioner are ('container', 'local')."
  }
}
