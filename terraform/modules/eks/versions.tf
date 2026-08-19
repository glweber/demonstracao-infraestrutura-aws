terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Required to read the OIDC issuer certificate when registering the identity
    # provider that underpins IRSA.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
