data "template_file" "runner_user_data" {
  template = file("user_data/install_runner.sh")
  vars = {
    num_runners = var.gitlab.runner_agents_per_instance
    gitlab_url = var.gitlab.uri
    registration_token = data.aws_ssm_parameter.runner_registration_token.value
    region = data.aws_region.current.name
    hookchecker_py_content = file("hookchecker/hookchecker.py")
    hookchecker_service_content  = file("hookchecker/hookchecker.service")
  }
}

resource "aws_launch_configuration" "runner" {
  name          = "gitlab-runner"
  image_id      = data.aws_ami.amazonlinux2.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.runner.id]
  spot_price    = "0.0146"
  user_data     = data.template_file.runner_user_data.rendered
  key_name      = var.ssh_access.key_name
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile = aws_iam_instance_profile.runner.name

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_autoscaling_group" "runner" {
  name                 = "gitlab-runner"
  launch_configuration = aws_launch_configuration.runner.name
  min_size             = var.asg.min_size
  max_size             = var.asg.max_size
  desired_capacity     = var.asg.desired_capacity
  vpc_zone_identifier  = var.asg.subnet_ids
  health_check_grace_period = 120

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "gitlab-runner"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_lifecycle_hook" "hook" {
  name                   = "terminate-runner"
  autoscaling_group_name = aws_autoscaling_group.runner.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 60
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}

//resource "aws_autoscaling_policy" "gitlab_runners_scale_out" {
//  name                   = "scale-out"
//  scaling_adjustment     = 1
//  adjustment_type        = "ChangeInCapacity"
//  cooldown               = 240
//  autoscaling_group_name = aws_autoscaling_group.runner.name
//}

resource "aws_autoscaling_policy" "gitlab_runners_scale_out" {
  name                   = "scale-out"
  adjustment_type        = "ChangeInCapacity"
  estimated_instance_warmup = 240
  autoscaling_group_name = aws_autoscaling_group.runner.name
  policy_type            = "StepScaling"
  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 1
    metric_interval_upper_bound = 2
  }
  step_adjustment {
    scaling_adjustment          = 2
    metric_interval_lower_bound = 2
  }
}

resource "aws_autoscaling_policy" "gitlab_runners_scale_in" {
  name                   = "scale-in"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.runner.name
}
