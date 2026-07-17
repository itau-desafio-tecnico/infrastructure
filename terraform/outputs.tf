output "alb_dns_name" {
  description = "Base URL dos servicos (/py-order-service*, /jv-requester-service*), Grafana (:3000) e Jaeger (:16686)"
  value       = module.ecs.alb_dns_name
}

output "grafana_admin_secret_arn" {
  description = "Secret no Secrets Manager com a senha do usuario admin do Grafana"
  value       = module.observability.grafana_admin_secret_arn
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
