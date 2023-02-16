# GPU

Create a runner that has a GPU attached. As this is expensive use the `gitlab.runner_job_tags` variable with value `gpu`
and tag your job within the `.gitlab-ci.yml` as per [configure_runners](https://docs.gitlab.com/ee/ci/yaml/#tags)) with
`gpu`. This will prevent the runner from creating these instances when a job does not require a GPU.

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

No outputs.
<!-- END_TF_DOCS -->
