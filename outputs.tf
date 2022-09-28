output "lambda_function_url" {
  description = "Public URL to be used by the GitLab webhook to trigger runner creation"
  value       = var.lambda.allow_function_url ? aws_lambda_function_url.push_gitlab_pending_jobs_metric[0].function_url : null
}
