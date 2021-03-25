resource "aws_iam_role" "ec2_runner" {
  name               = "gitlab-runner"
  assume_role_policy = file("${path.module}/iam/services/ec2.json")
}

data "template_file" "ec2_runner_policy" {
  template = file("${path.module}/iam/ec2_runner_policy.json")
  vars = {
    autoscaling_group_arn = aws_autoscaling_group.runner.arn
  }
}

resource "aws_iam_policy" "ec2_runner" {
  name        = "gitlab-runner-asg-hook-write-access"
  path        = "/"
  description = "gitlab-runner-asg-hook-write-access"

  policy = data.template_file.ec2_runner_policy.rendered
}

resource "aws_iam_policy_attachment" "asg-readonly-access-policy-attach" {
  name       = "gitlab-runner-asg-readonly-access-policy-attachment"
  roles      = [aws_iam_role.ec2_runner.name]
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingReadOnlyAccess"
}

resource "aws_iam_policy_attachment" "asg-hook-write-access-policy-attach" {
  name       = "gitlab-runner-asg-hook-write-access-policy-attachment"
  roles      = [aws_iam_role.ec2_runner.name]
  policy_arn = aws_iam_policy.ec2_runner.arn
}

resource "aws_iam_instance_profile" "runner" {
  name = "gitlab-runner-fra-instance-profile"
  role = aws_iam_role.ec2_runner.name
}

data "template_file" "lambda_gitlab_metric_policy" {
  template = file("${path.module}/iam/lambda_gitlab_metric_policy.json")
  vars = {
    region         = data.aws_region.current.name
    account_id     = data.aws_caller_identity.current.account_id
    parameter_path = var.gitlab.api_token_ssm_path
  }
}

resource "aws_iam_role" "lambda_gitlab_metric" {
  name               = "lambda-gitlab-metric"
  assume_role_policy = file("${path.module}/iam/services/lambda.json")
}

resource "aws_iam_policy" "lambda_gitlab_metric" {
  name        = "lambda-gitlab-metric-policy"
  path        = "/"
  description = "IAM policy for lambda push-gitlab-pending-jobs-metric"

  policy = data.template_file.lambda_gitlab_metric_policy.rendered
}

resource "aws_iam_role_policy_attachment" "lambda_gitlab_metric" {
  role       = aws_iam_role.lambda_gitlab_metric.name
  policy_arn = aws_iam_policy.lambda_gitlab_metric.arn
}
