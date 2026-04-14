terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "my-infra/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
  }
}

provider "aws" {
  region = var.region
}

resource "aws_instance" "app_server" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = var.instance_type

  tags = {
    Name        = "AppServer"
    Environment = "production"
  }
}

resource "aws_s3_bucket" "app_assets" {
  bucket = var.bucket_name

  tags = {
    Name        = "AppAssets"
    Environment = "production"
  }
}

