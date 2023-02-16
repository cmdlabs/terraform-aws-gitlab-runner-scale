# Volume

Customise the AMI root volume details.

The runners provide SSH connectivity using a public IP address that is accessible to the public internet. The public /
private key pair is generated via Terraform.

The instance has no additional AWS permissions with 1 t3.large instance always running to a maximum of 5.

The job queue check is run every 5 minutes.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |
| <a name="provider_local"></a> [local](#provider\_local) | n/a |
| <a name="provider_tls"></a> [tls](#provider\_tls) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_gitlab-runner"></a> [gitlab-runner](#module\_gitlab-runner) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_key_pair.key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [local_file.key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [tls_private_key.key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |

## Inputs

No inputs.

## Outputs

No outputs.
<!-- END_TF_DOCS -->
