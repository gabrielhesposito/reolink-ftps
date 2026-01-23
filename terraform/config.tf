terraform {
  backend "s3" {
    bucket         = "prod-personal-tfstate"
    key            = "tfstates/reolink-ftpss/terraform.tfstate"
    region         = "us-east-1"
    #dynamodb_table = "tf-prod-personal-state-lock"
    encrypt        = true
    #use_lockfile = true
    profile = "gespome"
  }

  
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      #version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  profile = "gespome"
  allowed_account_ids = [780770431026]
  #shared_credentials_files = ["~/.aws/login/cache/"]

}

