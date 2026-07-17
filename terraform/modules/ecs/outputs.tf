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
