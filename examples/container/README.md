# Container

The lambda dependencies are built from within a container (docker) requiring no python or pip installed programs
locally.

The runners provide SSH connectivity using a public IP address that is accessible to the public internet. The public /
private key pair is generated via Terraform.

The instance has no additional AWS permissions with 1 t3.large instance always running to a maximum of 5.

The job queue check is run every 5 minutes.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_gitlab-runner"></a> [gitlab-runner](#module\_gitlab-runner) | ../../ | n/a |

## Resources

No resources.

## Inputs

No inputs.

## Outputs

No outputs.
<!-- END_TF_DOCS -->
