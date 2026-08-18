terraform {

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "6.60.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
  }

  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "marco-callea-tfstate"
    key          = "envs/prod/watchdog.tfstate"
    region       = "eu-south-1"
    use_lockfile = true
  }

}

provider "aws" {
  region = "eu-south-1"
  default_tags {
    tags = { Project = "aws-security-watchdog", ManagedBy = "terraform", Environment = "prod" }
  }
}

