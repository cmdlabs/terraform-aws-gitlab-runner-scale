data "aws_iam_policy_document" "runner_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  assume_role_policy = data.aws_iam_policy_document.runner_assume_role.json
  name_prefix        = "gitlab-runner"
}

data "aws_iam_policy_document" "runner" {
  statement {
    actions = [
      "autoscaling:RecordLifecycleActionHeartbeat",
      "autoscaling:CompleteLifecycleAction",
    ]
    effect = "Allow"
    resources = [
      aws_autoscaling_group.runner.arn
    ]
  }
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    effect = "Allow"
    resources = [
      "${aws_cloudwatch_log_group.runner.arn}:*"
    ]
  }
}

resource "aws_iam_policy" "runner_job" {
  count = var.asg.job_policy != "" ? 1 : 0

  name_prefix = "gitlab-runner-job-permissions-"
  description = "Permissions required by the runner job to access AWS resources"
  path        = "/"
  policy      = var.asg.job_policy
}

resource "aws_iam_policy" "runner" {
  name_prefix = "gitlab-runner-asg-hook-write-access-"
  description = "gitlab-runner-asg-hook-write-access"
  path        = "/"
  policy      = data.aws_iam_policy_document.runner.json
}

resource "aws_iam_role_policy_attachment" "asg_hook_write_access" {
  policy_arn = aws_iam_policy.runner.arn
  role       = aws_iam_role.runner.name
}

resource "aws_iam_role_policy_attachment" "asg_readonly_access" {
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingReadOnlyAccess"
  role       = aws_iam_role.runner.name
}

resource "aws_iam_role_policy_attachment" "asg_runner_job" {
  count = var.asg.job_policy != "" ? 1 : 0

  policy_arn = aws_iam_policy.runner_job[0].arn
  role       = aws_iam_role.runner.name
}

resource "aws_iam_role_policy_attachment" "ssm_managed_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.runner.name
}

resource "aws_iam_role_policy_attachment" "managed_policy_arns" {
  for_each   = toset(var.asg.managed_policy_arns)
  policy_arn = each.value
  role       = aws_iam_role.runner.name
}

resource "aws_iam_instance_profile" "runner" {
  name_prefix = "gitlab-runner-instance-profile"
  role        = aws_iam_role.runner.name
}

data "aws_iam_policy_document" "lambda_gitlab_metric" {
  statement {
    actions = [
      "ssm:DescribeParameters",
      "cloudwatch:PutMetricData",
      "autoscaling:DescribeAutoScalingGroups",
    ]
    effect    = "Allow"
    resources = ["*"]
  }
  statement {
    actions = [
      "ssm:GetParameter",
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.gitlab.api_token_ssm_path}"
    ]
  }
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    effect = "Allow"
    resources = [
      "${aws_cloudwatch_log_group.lambda_push_gitlab_pending_jobs_metric.arn}:*"
    ]
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  name_prefix        = "lambda-gitlab-metric"
}

resource "aws_iam_policy" "lambda_gitlab_metric" {
  description = "IAM policy for lambda push-gitlab-pending-jobs-metric"
  name_prefix = "lambda-gitlab-metric-policy"
  path        = "/"
  policy      = data.aws_iam_policy_document.lambda_gitlab_metric.json
}

resource "aws_iam_role_policy_attachment" "lambda_gitlab_metric" {
  policy_arn = aws_iam_policy.lambda_gitlab_metric.arn
  role       = aws_iam_role.lambda.name
}
