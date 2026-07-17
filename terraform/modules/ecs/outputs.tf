output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "order_service_ecr_url" {
  value = aws_ecr_repository.order_service.repository_url
}

output "requester_service_ecr_url" {
  value = aws_ecr_repository.requester_service.repository_url
}

output "order_service_migration_ecr_url" {
  value = aws_ecr_repository.order_service_migration.repository_url
}

output "order_service_migration_task_family" {
  value = aws_ecs_task_definition.order_service_migration.family
}
