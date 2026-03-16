terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
backend "s3" {
    bucket = "11-9-backend"
    key    = "saopaulo/terraform.tfstate"
    region = "us-east-1"
  }

}

# São Paulo is a separate Terraform state.
# This provider file is standalone — it does NOT reference the Tokyo provider.
# Tokyo outputs are consumed via variables (see variables.tf).
provider "aws" {
  alias  = "saopaulo"
  region = "sa-east-1"
}

# Default provider required by Terraform even when all resources use alias.
provider "aws" {
  region = "sa-east-1"
}

# Tokyo provider alias — used only to read Secrets Manager secret
# that was created in ap-northeast-1 by the Tokyo state.
# Analogy: São Paulo needs to call Tokyo's locker room.
# This is the phone line that makes that call possible.
provider "aws" {
  alias  = "tokyo"
  region = "ap-northeast-1"
}

