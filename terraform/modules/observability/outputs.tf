output "otel_collector_endpoint" {
  description = "Endpoint OTLP/HTTP para os servicos exportarem traces/metricas"
  value       = "http://otel-collector.${var.service_discovery_namespace_name}:4318/v1/traces"
}

output "grafana_admin_secret_arn" {
  value = aws_secretsmanager_secret.grafana_admin.arn
}
