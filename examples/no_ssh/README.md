# No SSH

This runner provides no SSH connectivity as no key pair is provides or security group. A public IP address is required
to allow SSM to connect.

The instance also has limited AWS permissions to EC2 describe and SSM to perform commands.

The job queue check is run every minute.

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
