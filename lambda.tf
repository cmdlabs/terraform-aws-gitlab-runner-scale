locals {
  lambda_name         = "push-gitlab-pending-jobs-metric"
  lambda_folder       = "function"
  lambda_payload_name = "function_payload.zip"
}

resource "null_resource" "build" {
  triggers = {
    requirements = filebase64sha256("${path.module}/function/requirements.txt")
  }

  provisioner "local-exec" {
    command = "docker run --rm -v ${abspath(path.root)}/function:/root/ ${replace(var.lambda_runtime, "python", "python:")} pip3 install --no-compile -r /root/requirements.txt -t '/root'"
  }
}

# Trick to run the build command before archiving.
# See below for more detail.
# https://github.com/terraform-providers/terraform-provider-archive/issues/11
data "null_data_source" "build_dep" {
  inputs = {
    build_id   = null_resource.build.id
    source_dir = local.lambda_folder
  }
}

data "archive_file" "lambda_payload" {
  type        = "zip"
  source_dir  = data.null_data_source.build_dep.outputs.source_dir
  output_path = local.lambda_payload_name
}

resource "aws_lambda_function" "push_gitlab_pending_jobs_metric" {
  filename      = local.lambda_payload_name
  function_name = local.lambda_name
  role          = aws_iam_role.lambda_gitlab_metric.arn
  handler       = "${local.lambda_name}.handler"
  timeout       = 60
  memory_size   = 512

  runtime = var.lambda_runtime

  source_code_hash = data.archive_file.lambda_payload.output_base64sha256

  environment {
    variables = {
      GITLAB_URI           = var.gitlab.uri
      TOKEN_SSM_PATH       = var.gitlab.api_token_ssm_path
      ASG_NAME             = aws_autoscaling_group.runner.name
      RUNNERS_PER_INSTANCE = var.gitlab.runner_agents_per_instance
      NARROW_TO_MEMBERSHIP = var.gitlab.narrow_to_membership
      LOG_LEVEL            = var.gitlab.log_level
    }
  }

}

resource "aws_lambda_permission" "push_gitlab_pending_jobs_metric" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.push_gitlab_pending_jobs_metric.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_push_gitlab_pending_jobs_metric.arn
}
