# Custom VPC

We create a custom VPC and deploy the runner into the VPC private subnets.

This runner provides no SSH connectivity as no key pair is provides or security group and is not provide as the NAT
gateway can be used to connect via SSM.

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
| <a name="module_vpc"></a> [vpc](#module\_vpc) | github.com/cmdlabs/cmd-tf-aws-vpc | 0.12.0 |

## Resources

No resources.

## Inputs

No inputs.

## Outputs

No outputs.
<!-- END_TF_DOCS -->
