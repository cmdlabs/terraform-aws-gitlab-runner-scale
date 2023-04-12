locals {
  provisioner_command = {
    container = "docker run --rm -v ${abspath(path.root)}/function:/root/ ${replace(var.lambda.runtime, "python", "python:")} pip3 install --no-compile -r /root/requirements.txt -t /root"
    local     = "pip3 install --no-compile -r ${path.module}/function/requirements.txt -t ${path.module}/function/"
  }
}

resource "null_resource" "build" {
  provisioner "local-exec" {
    command = local.provisioner_command[var.provisioner]
  }
  triggers = {
    # Protect against new module download or pip downloads changed. Terraform cannot glob 256 a dir or get all files and sum the sha256
    # Also ignore the zip itself as it could change and may cause unnecessary reruns
    # May trigger twice as the download of the modules on the first run will change the checksum
    directory = sha256(join("", [for f in fileset(local.lambda_folder, "**") : filesha256("${local.lambda_folder}/${f}") if "${local.lambda_folder}/${f}" != local.lambda_payload_name]))
  }
}

data "archive_file" "lambda_payload" {
  excludes = [
    local.lambda_payload_zip_name
  ]
  output_path = local.lambda_payload_name
  source_dir  = local.lambda_folder
  type        = "zip"

  depends_on = [null_resource.build]
}

resource "aws_lambda_function" "push_gitlab_pending_jobs_metric" {
  filename      = local.lambda_payload_name
  function_name = "${local.lambda_name}-${random_string.rule_suffix.result}"
  handler       = "${local.lambda_name}.handler"
  layers = [
    local.parameter_layer[data.aws_region.current.name]
  ]
  memory_size = var.lambda.memory_size
  # We only need this to run once as it will check the gitlab job api and return a result for all relevant jobs.
  # Running multiple times will just increase cost
  # It may lead to 429 TooManyRequestsException or Rate exceeded but these can be ignored
  reserved_concurrent_executions = 1
  role                           = aws_iam_role.lambda.arn
  runtime                        = var.lambda.runtime
  source_code_hash               = data.archive_file.lambda_payload.output_base64sha256
  timeout                        = 10

  environment {
    variables = {
      ACTIVITY_SINCE       = var.gitlab.activity_since_hours
      ALLOWED_IP_RANGE     = var.gitlab.allowed_ip_range
      ASG_NAME             = aws_autoscaling_group.runner.name
      GITLAB_URI           = var.gitlab.uri
      LOG_LEVEL            = var.gitlab.log_level
      METRIC_NAMESPACE     = local.metric_namespace
      NARROW_TO_MEMBERSHIP = var.gitlab.narrow_to_membership
      RUNNER_JOB_TAGS      = local.asg_tag_list
      RUNNERS_PER_INSTANCE = var.gitlab.runner_agents_per_instance
      TOKEN_SSM_PATH       = var.gitlab.api_token_ssm_path
    }
  }
}

resource "aws_lambda_function_url" "push_gitlab_pending_jobs_metric" {
  count = var.lambda.allow_function_url ? 1 : 0

  function_name = aws_lambda_function.push_gitlab_pending_jobs_metric.function_name
  # As its coming from a POST from gitlab we have no AWS_IAM authentication we can apply
  authorization_type = "NONE"

  cors {
    allow_credentials = var.lambda.cors.allow_credentials
    allow_headers     = var.lambda.cors.allow_headers
    allow_methods     = var.lambda.cors.allow_methods
    allow_origins     = var.lambda.cors.allow_origins
    expose_headers    = var.lambda.cors.expose_headers
    max_age           = var.lambda.cors.max_age
  }
}

resource "aws_lambda_permission" "push_gitlab_pending_jobs_metric" {
  count = var.lambda.rate != "off" ? 1 : 0

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.push_gitlab_pending_jobs_metric.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_push_gitlab_pending_jobs_metric[0].arn
  statement_id  = "AllowExecutionFromCloudWatch"
}
