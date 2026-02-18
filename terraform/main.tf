

#####################################################################################
# Terraform module examples are meant to show an _example_ on how to use a module
# per use-case. The code below should not be copied directly but referenced in order
# to build your own root module that invokes this module
#####################################################################################

######################################
# Defaults and Locals
######################################

resource "random_pet" "name" {
  prefix = "aws-ia"
  length = 1
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  server_name = "prod-personal-transfer-server"
  # users                     = var.users_file != null ? (fileexists(var.users_file) ? csvdecode(file(var.users_file)) : []) : [] # Read users from CSV
  vpc_id          = module.vpc.vpc_attributes.id
  public_subnets  = flatten([for _, value in module.vpc.public_subnet_attributes_by_az : [value.id]])
  private_subnets = flatten([for _, value in module.vpc.private_subnet_attributes_by_az : [value.id]])
  #ingress_cidr_blocks_list  = [for cidr in split(",", var.sftp_ingress_cidr_block) : trimspace(cidr)]
  #egress_cidr_blocks_list   = [for cidr in split(",", var.sftp_egress_cidr_block) : trimspace(cidr)]
  az_count = 2
}

data "aws_caller_identity" "current" {}

###################################################################
# Transfer Server example usage
###################################################################
module "transfer_server" {
  source = "aws-ia/transfer-family/aws"

  domain        = "S3"
  protocols     = ["FTPS"]
  endpoint_type = "VPC"
  endpoint_details = {
    address_allocation_ids = aws_eip.sftp[*].allocation_id
    security_group_ids     = [aws_security_group.sftp.id]
    subnet_ids             = local.public_subnets
    vpc_id                 = local.vpc_id
  }
  acm_certificate_arn      = module.acm_request_certificate.arn
  server_name              = "prod-personal-transfer-server"
  dns_provider             = "route53"
  custom_hostname          = "ftps.gespo.me"
  route53_hosted_zone_name = "Z385B2JMGHKW93"
  identity_provider        = "AWS_DIRECTORY_SERVICE"
  security_policy_name     = "TransferSecurityPolicy-2024-01" # https://docs.aws.amazon.com/transfer/latest/userguide/security-policies.html#security-policy-transfer-2024-01
  enable_logging           = true
  log_retention_days       = 30 # This can be modified based on requirements
  log_group_kms_key_id     = aws_kms_key.transfer_family_key.arn
  logging_role             = null
  workflow_details         = null
  directory_id             = module.ad.directory_id
}


module "acm_request_certificate" {
  source = "cloudposse/acm-request-certificate/aws"
  # Cloud Posse recommends pinning every module to a specific version
  version                           = "v0.18.1"
  domain_name                       = "ftps.gespo.me"
  process_domain_validation_options = true
  ttl                               = "300"
  zone_id                           = "Z385B2JMGHKW93"
}

#module "sftp_users" {
#  source = "aws-ia/transfer-family/aws//modules/transfer-users"
#    users  = local.users
#  create_test_user = true # Test user is for demo purposes. Key and Access Management required for the created secrets 

# server_id = module.transfer_server.server_id

#s3_bucket_name = module.s3_bucket.s3_bucket_id
#s3_bucket_arn  = module.s3_bucket.s3_bucket_arn

#kms_key_id = aws_kms_key.transfer_family_key.arn
#}

###################################################################
# Create VPC for Transfer Server
###################################################################
module "vpc" {
  source = "git::https://github.com/aws-ia/terraform-aws-vpc.git?ref=v4.7.3"

  name       = "${local.server_name}-vpc"
  cidr_block = "10.0.0.0/21"
  az_count   = local.az_count

  subnets = {
    public = {
      name_prefix               = "${local.server_name}-public-subnet"
      netmask                   = 27
      nat_gateway_configuration = "all_azs" # options: "single_az", "none"
    }
    private = {
      name_prefix               = "${local.server_name}-private-subnet"
      netmask                   = 27
      nat_gateway_configuration = "all_azs" # options: "single_az", "none"
    }
  }
}

resource "aws_eip" "sftp" {
  # checkov:skip=CKV2_AWS_19: EIPs are used for AWS Transfer Family VPC endpoints, not EC2 instances
  count = local.az_count
  tags = {
    Name = "${local.server_name}-sftp-eip-${count.index + 1}"
  }
}

resource "aws_security_group" "sftp" {
  name                   = "${local.server_name}-sftp-sg"
  description            = "Security group for VPC endpoint of AWS Transfer Family SFTP"
  vpc_id                 = local.vpc_id
  revoke_rules_on_delete = true

  tags = {
    Environment = "prod"
    Name        = "${local.server_name}-sftp-sg"
  }
}

#resource "aws_vpc_security_group_ingress_rule" "sftp_ingress" {
#  for_each          = toset(local.ingress_cidr_blocks_list)
#  security_group_id = aws_security_group.sftp.id
#  description       = "Allow inbound SFTP (TCP/22) from ${each.value}"
#  ip_protocol       = "tcp"
#  from_port         = 22
#  to_port           = 22
#  cidr_ipv4         = each.value

# tags = {
#  Name = "${local.server_name}-sftp-ingress-${index(local.ingress_cidr_blocks_list, each.value)}"
#}
#}

# Separate Egress Rule for SFTP
#resource "aws_vpc_security_group_egress_rule" "sftp_egress" {
#  for_each          = toset(local.egress_cidr_blocks_list)
#  security_group_id = aws_security_group.sftp.id
# description       = "Allow outbound traffic"
# ip_protocol       = "-1"
# cidr_ipv4         = each.value

#tags = {
# Name = "${local.server_name}-sftp-egress-${index(local.egress_cidr_blocks_list, each.value)}"
#}
#}

###################################################################
# Create S3 bucket for Transfer Server (Optional if already exists)
###################################################################
module "s3_bucket" {
  source                   = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=v5.0.0"
  bucket                   = lower("${random_pet.name.id}-${random_id.suffix.hex}-${module.transfer_server.server_id}-s3-ftps")
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"
  block_public_acls        = true
  block_public_policy      = true
  ignore_public_acls       = true
  restrict_public_buckets  = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.transfer_family_key.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  versioning = {
    enabled = false # Turn on versioning if needed
  }
}

###################################################################
# KMS key and policies for Transfer Server
###################################################################

# KMS Key resource
resource "aws_kms_key" "transfer_family_key" {
  description             = "KMS key for encrypting S3 bucket and cloudwatch log group"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Purpose = "Transfer Family Encryption"
  }
}

# KMS Key Alias
resource "aws_kms_alias" "transfer_family_key_alias" {
  name          = "alias/transfer-family-key-${random_pet.name.id}"
  target_key_id = aws_kms_key.transfer_family_key.key_id
}

# KMS Key Policy
resource "aws_kms_key_policy" "transfer_family_key_policy" {
  key_id = aws_kms_key.transfer_family_key.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable Limited Admin Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = aws_kms_key.transfer_family_key.arn
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.us-east-1.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = aws_kms_key.transfer_family_key.arn
      }
    ]
  })
}

###################################################################
# Create AD via AWS Directory Service
###################################################################

##-----------------------------------------------------------------------------
## Simple Active Directory Module
## This module sets up a Simple Active Directory within the specified VPC and subnets.
##-----------------------------------------------------------------------------


module "ad" {
  source         = "git::https://github.com/clouddrove/terraform-aws-active-directory.git?ref=1.0.3"
  environment    = "test"
  name           = "ad-reolink"
  label_order    = ["name", "environment"]
  directory_type = "SimpleAD"
  subnet_ids     = local.public_subnets
  vpc_settings   = { vpc_id : local.vpc_id, subnet_ids : join(",", local.public_subnets) }
  directory_name = "ad.gespo.me"
  ad_password    = "xyz123@abc"
  ip_rules       = var.ip_rules

  # Additional optional parameters for more features
  edition     = "Standard" # Can be "Standard" or "Enterprise"
  short_name  = "clouddrove"
  description = "Simple AD for reolink Storage"
  enable_sso  = false
  # Set to true to enable Single Sign-On (SSO) for Microsoft AD
  # Uncomment the following line to set an alias for the Microsoft AD
  # alias       = "clouddrove-ad"
}