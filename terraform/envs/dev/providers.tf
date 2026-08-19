# Tags applied by the provider to every taggable resource. Cost allocation and
# ownership queries depend on these being present without exception, which is not
# achievable by tagging each resource individually.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = local.environment
      Project     = var.project
      Owner       = var.owner
      ManagedBy   = "terraform"
      Repository  = "demonstracao-infraestrutura-aws"
    }
  }
}
