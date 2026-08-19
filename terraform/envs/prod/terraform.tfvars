# Production environment values.
#
# operator_access_cidrs is documentation-only in this repository and uses the
# RFC 5737 reserved range. Replace it with the egress addresses of the office or
# VPN before any real initialisation.

region                = "eu-west-1"
project               = "demonstration-platform"
owner                 = "platform-engineering"
vpc_cidr              = "10.20.0.0/16"
kubernetes_version    = "1.31"
operator_access_cidrs = ["203.0.113.0/24"]
