resource "random_string" "rule_suffix" {
  length  = 8
  lower   = true
  special = false
}

resource "aws_cloudwatch_event_rule" "lambda_push_gitlab_pending_jobs_metric" {
  count = var.lambda.rate != "off" ? 1 : 0

  name_prefix         = "lambda-push-gitlab-pending-jobs-metric"
  description         = "Trigger the lambda push-gitlab-pending-jobs-metric"
  schedule_expression = var.lambda.rate
}

resource "aws_cloudwatch_event_target" "lambda_push_gitlab_pending_jobs_metric" {
  count = var.lambda.rate != "off" ? 1 : 0

  arn  = aws_lambda_function.push_gitlab_pending_jobs_metric.arn
  rule = aws_cloudwatch_event_rule.lambda_push_gitlab_pending_jobs_metric[0].name
}

resource "aws_cloudwatch_log_group" "lambda_push_gitlab_pending_jobs_metric" {
  name              = "/aws/lambda/${aws_lambda_function.push_gitlab_pending_jobs_metric.function_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_metric_alarm" "gitlab_pending_jobs" {
  alarm_actions       = [aws_autoscaling_policy.gitlab_runners_scale_out.arn]
  alarm_description   = "This metric monitors the presence of pending jobs in gitlab ${var.gitlab.uri}"
  alarm_name          = "GitlabPendingJobs-${random_string.rule_suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    "Job Status" = "Pending"
  }
  evaluation_periods        = "1"
  insufficient_data_actions = []
  metric_name               = "NumberOfPendingJobs"
  namespace                 = local.metric_namespace
  period                    = "10"
  statistic                 = "Average"
  threshold                 = "0"
}

resource "aws_cloudwatch_metric_alarm" "gitlab_reduntant_runners" {
  alarm_actions       = [aws_autoscaling_policy.gitlab_runners_scale_in.arn]
  alarm_description   = "This metric monitors the load of runners in gitlab ${var.gitlab.uri}"
  alarm_name          = "GitlabRedundantRunners-${random_string.rule_suffix.result}"
  comparison_operator = "LessThanThreshold"
  datapoints_to_alarm = var.gitlab.runner_idletime
  dimensions = {
    "Runners Overall Load" = "OverallLoadPercentage"
  }
  evaluation_periods        = var.gitlab.runner_idletime
  insufficient_data_actions = []
  metric_name               = "RunnersOverallLoad"
  namespace                 = local.metric_namespace
  period                    = "60"
  statistic                 = "Minimum"
  threshold                 = "80"
}
