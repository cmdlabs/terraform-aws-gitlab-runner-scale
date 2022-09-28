# Public webhook from GitLab

We configure a [GitLab webhook](https://docs.gitlab.com/ee/user/project/integrations/webhooks.html) that makes a call to
a public [function url](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html) for the lambda function. This way
the lambda runs on demand to speed up the check of the job queue.

The webhook requires the following triggers:

* Push Events
* Job Events
* Pipeline Events
* SSL Verification: enabled

_NOTE:_ The function has no security so the endpoint can be accessed from anywhere. The lambda does not output any data
and has a reserved concurrency of _1_ to reduce the chance of misuse.

The default EventBridge rule is turned off so the lambda only triggers on webhook call, not polling.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 4.39.0 |

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

No outputs.
<!-- END_TF_DOCS -->
