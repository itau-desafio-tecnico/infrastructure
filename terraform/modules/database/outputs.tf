output "order_db_endpoint" {
  value = aws_db_instance.order.address
}

output "requester_db_endpoint" {
  value = aws_db_instance.requester.address
}

output "order_db_secret_arn" {
  value = aws_secretsmanager_secret.order_db.arn
}

output "requester_db_secret_arn" {
  value = aws_secretsmanager_secret.requester_db.arn
}
