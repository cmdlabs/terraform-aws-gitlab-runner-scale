locals {
  executor = (
    var.asg.executor == "docker" ?
    "--executor 'docker' --docker-image alpine:latest --docker-privileged --description \"docker-runner $${INSTANCE_ID}\"" :
    "--executor 'shell' --description \"shell-runner $${INSTANCE_ID}\""
  )
}
resource "aws_launch_template" "runner" {
  block_device_mappings {
    device_name = lookup(var.asg.root_block_device, "name", "/dev/xvda")
    ebs {
      delete_on_termination = lookup(var.asg.root_block_device, "delete_on_termination", true)
      encrypted             = lookup(var.asg.root_block_device, "encrypted", true)
      iops                  = lookup(var.asg.root_block_device, "iops", null)
      throughput            = lookup(var.asg.root_block_device, "throughput", null)
      volume_size           = lookup(var.asg.root_block_device, "volume_size", null)
      volume_type           = lookup(var.asg.root_block_device, "volume_type", "gp3")
    }
  }
  iam_instance_profile {
    name = aws_iam_instance_profile.runner.name
  }
  image_id = var.asg.image_id == "" ? data.aws_ami.amazonlinux2[0].id : var.asg.image_id
  # Dynamic due to https://github.com/hashicorp/terraform-provider-aws/issues/24009
  dynamic "instance_market_options" {
    for_each = var.asg.spot_price != null ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price          = var.asg.spot_price == "" ? null : var.asg.spot_price
        spot_instance_type = "one-time"
      }
    }
  }
  instance_type = var.asg.instance_type
  key_name      = var.asg.ssh_access.key_name
  name_prefix   = "gitlab-runner-"
  network_interfaces {
    associate_public_ip_address = var.asg.associate_public_ip_address
    security_groups             = [aws_security_group.runner.id]
  }
  update_default_version = true
  user_data = base64encode(templatefile("${path.module}/templates/user_data/install_runner.sh.tpl", {
    executor      = local.executor
    executor_type = var.asg.executor
    gitlab_url    = var.gitlab.uri
    hookchecker_py_content = templatefile(
      "${path.module}/templates/hookchecker/hookchecker.py",
      {
        LOG_LEVEL = var.asg.log_level,
      },
    )
    hookchecker_service_content = file("${path.module}/templates/hookchecker/hookchecker.service")
    log_group                   = aws_cloudwatch_log_group.runner.name
    num_runners                 = var.gitlab.runner_agents_per_instance
    project_id                  = var.gitlab.project_id
    region                      = data.aws_region.current.name
    runner_registration_type    = var.gitlab.runner_registration_type
    runner_job_tags             = local.asg_tag_list
    runner_token_ssm_path       = var.gitlab.runner_registration_token_ssm_path
    runner_version              = var.gitlab.runner_version
  }))

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "runner" {
  desired_capacity          = var.asg.desired_capacity != -1 ? var.asg.desired_capacity : null
  health_check_grace_period = 120
  launch_template {
    id      = aws_launch_template.runner.id
    version = "$Latest"
  }
  max_size    = var.asg.max_size
  min_size    = var.asg.min_size
  name_prefix = "gitlab-runner-"
  termination_policies = [
    "OldestInstance"
  ]
  vpc_zone_identifier = var.asg.subnet_ids

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      desired_capacity # changes via autoscaling so we need to ignore this on redeploy
    ]
  }

  tag {
    key                 = "Name"
    value               = "gitlab-runner"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_lifecycle_hook" "hook" {
  autoscaling_group_name = aws_autoscaling_group.runner.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = var.asg.force_instance_deletion_time
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  name                   = "terminate-runner"
}

resource "aws_autoscaling_policy" "gitlab_runners_scale_out" {
  adjustment_type           = "ChangeInCapacity"
  autoscaling_group_name    = aws_autoscaling_group.runner.name
  estimated_instance_warmup = var.asg.scaling_warmup
  name                      = "scale-out"
  policy_type               = "StepScaling"
  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 0.1
    metric_interval_upper_bound = 2
  }
  step_adjustment {
    scaling_adjustment          = 2
    metric_interval_lower_bound = 2
  }
}

resource "aws_autoscaling_policy" "gitlab_runners_scale_in" {
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.runner.name
  name                   = "scale-in"
  policy_type            = "StepScaling"
  step_adjustment {
    scaling_adjustment          = -1
    metric_interval_lower_bound = -79
    metric_interval_upper_bound = 0
  }
  step_adjustment {
    scaling_adjustment          = -var.asg.max_size
    metric_interval_upper_bound = -79
  }
}

resource "aws_cloudwatch_log_group" "runner" {
  name              = "/gitlab/runner/logs-${random_string.rule_suffix.result}"
  retention_in_days = 30
}
