output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "ecs_tasks_security_group_id" {
  value = module.security.ecs_tasks_sg_id
}

output "order_service_ecr_url" {
  value = module.ecs.order_service_ecr_url
}

output "requester_service_ecr_url" {
  value = module.ecs.requester_service_ecr_url
}

output "order_service_migration_ecr_url" {
  value = module.ecs.order_service_migration_ecr_url
}

output "order_service_migration_task_family" {
  value = module.ecs.order_service_migration_task_family
}
