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

  depends_on = [module.network]
}

module "database" {
  source = "./modules/database"

  name_prefix        = local.name_prefix
  private_subnet_ids = module.network.private_subnet_ids
  rds_sg_id          = module.security.rds_sg_id
  db_instance_class  = var.db_instance_class

  depends_on = [module.network, module.security]
}

module "messaging" {
  source = "./modules/messaging"

  name_prefix = local.name_prefix
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_service_discovery_private_dns_namespace" "internal" {
  name = "internal.local"
  vpc  = module.network.vpc_id
}

locals {
  otel_collector_endpoint = "http://otel-collector.${aws_service_discovery_private_dns_namespace.internal.name}:4318/v1/traces"
}

module "ecs" {
  source = "./modules/ecs"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  alb_sg_id          = module.security.alb_sg_id
  ecs_tasks_sg_id    = module.security.ecs_tasks_sg_id
  ecs_cluster_id     = aws_ecs_cluster.this.id

  service_discovery_namespace_id   = aws_service_discovery_private_dns_namespace.internal.id
  service_discovery_namespace_name = aws_service_discovery_private_dns_namespace.internal.name

  order_db_endpoint       = module.database.order_db_endpoint
  requester_db_endpoint   = module.database.requester_db_endpoint
  order_db_secret_arn     = module.database.order_db_secret_arn
  requester_db_secret_arn = module.database.requester_db_secret_arn

  sns_topic_arn           = module.messaging.sns_topic_arn
  otel_collector_endpoint = local.otel_collector_endpoint

  order_service_image     = var.order_service_image
  requester_service_image = var.requester_service_image

  order_service_desired_count     = var.order_service_desired_count
  requester_service_desired_count = var.requester_service_desired_count

  order_service_min_capacity     = var.order_service_min_capacity
  order_service_max_capacity     = var.order_service_max_capacity
  order_service_cpu_target_value = var.order_service_cpu_target_value

  requester_service_min_capacity     = var.requester_service_min_capacity
  requester_service_max_capacity     = var.requester_service_max_capacity
  requester_service_cpu_target_value = var.requester_service_cpu_target_value
}

module "observability" {
  source = "./modules/observability"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  ecs_tasks_sg_id    = module.security.ecs_tasks_sg_id
  ecs_cluster_id     = aws_ecs_cluster.this.id
  alb_arn            = module.ecs.alb_arn

  service_discovery_namespace_id   = aws_service_discovery_private_dns_namespace.internal.id
  service_discovery_namespace_name = aws_service_discovery_private_dns_namespace.internal.name
}