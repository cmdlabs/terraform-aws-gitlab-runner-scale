resource "aws_cloudwatch_event_rule" "lambda_push_gitlab_pending_jobs_metric" {
  name        = "lambda-push-gitlab-pending-jobs-metric"
  description = "Trigger the lambda push-gitlab-pending-jobs-metric"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "lambda_push_gitlab_pending_jobs_metric" {
  rule      = aws_cloudwatch_event_rule.lambda_push_gitlab_pending_jobs_metric.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.push_gitlab_pending_jobs_metric.arn
}

resource "aws_cloudwatch_log_group" "lambda_push_gitlab_pending_jobs_metric" {
  name              = "/aws/lambda/${aws_lambda_function.push_gitlab_pending_jobs_metric.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_metric_alarm" "gitlab_pending_jobs" {
  alarm_name                = "GitlabPendingJobs"
  comparison_operator       = "GreaterThanThreshold"
  threshold                 = "0"
  evaluation_periods        = "2"
  metric_name               = "NumberOfPendingJobs"
  namespace                 = "GitLab"
  dimensions = {
    "Job Status" = "Pending"
  }
  period                    = "60"
  statistic                 = "Average"
  alarm_description         = "This metric monitors the presence of pending jobs in gitlab ${var.gitlab.uri}"
  insufficient_data_actions = []
  alarm_actions             = [aws_autoscaling_policy.gitlab_runners_scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "gitlab_reduntant_runners" {
  alarm_name                = "GitlabRedundantRunners"
  comparison_operator       = "LessThanThreshold"
  threshold                 = "80"
  evaluation_periods        = "2"
  metric_name               = "RunnersOverallLoad"
  namespace                 = "GitLab"
  dimensions = {
    "Runners Overall Load" = "OverallLoadPercentage"
  }
  period                    = "60"
  statistic                 = "Average"
  alarm_description         = "This metric monitors the load of runners in gitlab ${var.gitlab.uri}"
  insufficient_data_actions = []
  alarm_actions             = [aws_autoscaling_policy.gitlab_runners_scale_in.arn]
}
