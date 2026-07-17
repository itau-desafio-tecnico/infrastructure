locals {
  name_prefix = "desafio-${var.environment}"
}

module "network" {
  source = "./modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
}

module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
}

module "database" {
  source = "./modules/database"

  name_prefix        = local.name_prefix
  private_subnet_ids = module.network.private_subnet_ids
  rds_sg_id          = module.security.rds_sg_id
  db_instance_class  = var.db_instance_class
}