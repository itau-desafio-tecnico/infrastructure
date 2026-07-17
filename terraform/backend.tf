terraform {
  backend "s3" {
    bucket         = "itau-desafio-tecnico-tfstate"
    key            = "infra/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "itau-desafio-tecnico-terraform-locks"
    encrypt        = true
  }
}