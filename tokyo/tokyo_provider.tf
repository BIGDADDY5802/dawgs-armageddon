terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "11-9-backend"
    key    = "tokyo/terraform.tfstate"
    region = "us-east-1"
  }
}

# Tokyo is the default provider — all resources in this state deploy to ap-northeast-1.
provider "aws" {
  region = "ap-northeast-1"
}

# us-east-1 required for ACM certs used by CloudFront
provider "aws" {
  alias  = "useast1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "tokyo"
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "saopaulo"
  region = "sa-east-1"
}