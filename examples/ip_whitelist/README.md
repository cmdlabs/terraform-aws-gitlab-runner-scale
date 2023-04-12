# Whitelist within Function

To trigger execution using the lambda [function url](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html) and
GitLab webhooks, you can configure the `gitlab.allowed_ip_range` as a CIDR range of the source(s) calling the URL. Given
that the security of the function is set to `authorization_type = "NONE"` (for more information, refer to
[url auth](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html)) it provides very basic ip based protection from
overuse. Requests originating from outside the specified IP range will be quickly rejected with no message. The CIDR
range format follows the standard notation, for instance, `"34.74.90.64/28,34.74.226.0/24"`.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_gitlab-runner"></a> [gitlab-runner](#module\_gitlab-runner) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_subnets.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_lambda_function_url"></a> [lambda\_function\_url](#output\_lambda\_function\_url) | Public URL to be used by the GitLab webhook to trigger runner creation |
<!-- END_TF_DOCS -->
