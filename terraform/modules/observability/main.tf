# Stack de observabilidade self-hosted (ADR 0005): OTel Collector recebe
# OTLP dos dois microsservicos, exporta metricas para o Prometheus e
# traces para o Jaeger; o Grafana consulta os dois como datasources.
#
# Simplificacoes assumidas dado o escopo do desafio: sem armazenamento
# persistente (EFS) para Prometheus/Grafana - dados sao perdidos se o
# task reiniciar - e sem alta disponibilidade (1 task por componente).
# Logs de aplicacao continuam via CloudWatch Logs (ja configurado nas
# task definitions do modulo ecs); esta stack cobre metricas e tracing.

locals {
  otel_collector_config = <<-YAML
    receivers:
      otlp:
        protocols:
          http:
            endpoint: 0.0.0.0:4318
          grpc:
            endpoint: 0.0.0.0:4317
    exporters:
      otlp/jaeger:
        endpoint: jaeger.${var.service_discovery_namespace_name}:4317
        tls:
          insecure: true
      prometheus:
        endpoint: 0.0.0.0:9464
    service:
      pipelines:
        traces:
          receivers: [otlp]
          exporters: [otlp/jaeger]
        metrics:
          receivers: [otlp]
          exporters: [prometheus]
  YAML

  prometheus_config = <<-YAML
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: otel-collector
        static_configs:
          - targets: ["otel-collector.${var.service_discovery_namespace_name}:9464"]
      - job_name: requester-service
        metrics_path: /jv-requester-service/actuator/prometheus
        static_configs:
          - targets: ["requester-service.${var.service_discovery_namespace_name}:8081"]
  YAML

  grafana_datasources = <<-YAML
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus.${var.service_discovery_namespace_name}:9090
        isDefault: true
      - name: Jaeger
        type: jaeger
        access: proxy
        url: http://jaeger.${var.service_discovery_namespace_name}:16686
  YAML
}

resource "aws_cloudwatch_log_group" "observability" {
  for_each          = toset(["otel-collector", "prometheus", "grafana", "jaeger"])
  name              = "/ecs/${var.name_prefix}/${each.value}"
  retention_in_days = 14
}

resource "aws_iam_role" "observability_execution" {
  name = "${var.name_prefix}-observability-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "observability_execution_managed" {
  role       = aws_iam_role.observability_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "random_password" "grafana_admin" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "${var.name_prefix}/grafana/admin-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id     = aws_secretsmanager_secret.grafana_admin.id
  secret_string = random_password.grafana_admin.result
}

resource "aws_iam_role_policy" "observability_execution_secrets" {
  name = "${var.name_prefix}-observability-execution-secrets"
  role = aws_iam_role.observability_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.grafana_admin.arn]
    }]
  })
}

# ---------------------------------------------------------------------------
# OTel Collector
# ---------------------------------------------------------------------------

resource "aws_service_discovery_service" "otel_collector" {
  name = "otel-collector"
  dns_config {
    namespace_id = var.service_discovery_namespace_id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "otel_collector" {
  family                   = "${var.name_prefix}-otel-collector"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.observability_execution.arn

  container_definitions = jsonencode([
    {
      name      = "otel-collector"
      image     = "otel/opentelemetry-collector-contrib:0.108.0"
      essential = true
      command   = ["--config=env:OTEL_COLLECTOR_CONFIG"]
      environment = [
        { name = "OTEL_COLLECTOR_CONFIG", value = local.otel_collector_config }
      ]
      portMappings = [
        { containerPort = 4317, protocol = "tcp" },
        { containerPort = 4318, protocol = "tcp" },
        { containerPort = 9464, protocol = "tcp" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.observability["otel-collector"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "otel-collector"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "otel_collector" {
  name            = "otel-collector"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.otel_collector.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [var.ecs_tasks_sg_id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.otel_collector.arn
  }
}

# ---------------------------------------------------------------------------
# Prometheus
# ---------------------------------------------------------------------------

resource "aws_service_discovery_service" "prometheus" {
  name = "prometheus"
  dns_config {
    namespace_id = var.service_discovery_namespace_id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.name_prefix}-prometheus"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.observability_execution.arn

  container_definitions = jsonencode([
    {
      name      = "prometheus"
      image     = "prom/prometheus:v2.54.1"
      essential = true
      entryPoint = ["sh", "-c"]
      command = [
        "echo \"$PROMETHEUS_CONFIG\" > /etc/prometheus/prometheus.yml && exec /bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus"
      ]
      environment = [
        { name = "PROMETHEUS_CONFIG", value = local.prometheus_config }
      ]
      portMappings = [{ containerPort = 9090, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.observability["prometheus"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "prometheus"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "prometheus" {
  name            = "prometheus"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [var.ecs_tasks_sg_id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.prometheus.arn
  }
}

# ---------------------------------------------------------------------------
# Jaeger
# ---------------------------------------------------------------------------

resource "aws_service_discovery_service" "jaeger" {
  name = "jaeger"
  dns_config {
    namespace_id = var.service_discovery_namespace_id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_lb_target_group" "jaeger" {
  name        = "${var.name_prefix}-jaeger-tg"
  port        = 16686
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "jaeger" {
  load_balancer_arn = var.alb_arn
  port              = 16686
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jaeger.arn
  }
}

resource "aws_ecs_task_definition" "jaeger" {
  family                   = "${var.name_prefix}-jaeger"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.observability_execution.arn

  container_definitions = jsonencode([
    {
      name      = "jaeger"
      image     = "jaegertracing/all-in-one:1.60"
      essential = true
      environment = [
        { name = "COLLECTOR_OTLP_ENABLED", value = "true" }
      ]
      portMappings = [
        { containerPort = 16686, protocol = "tcp" },
        { containerPort = 4317, protocol = "tcp" },
        { containerPort = 4318, protocol = "tcp" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.observability["jaeger"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "jaeger"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "jaeger" {
  name            = "jaeger"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.jaeger.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [var.ecs_tasks_sg_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jaeger.arn
    container_name   = "jaeger"
    container_port   = 16686
  }

  service_registries {
    registry_arn = aws_service_discovery_service.jaeger.arn
  }

  depends_on = [aws_lb_listener.jaeger]
}

# ---------------------------------------------------------------------------
# Grafana
# ---------------------------------------------------------------------------

resource "aws_lb_target_group" "grafana" {
  name        = "${var.name_prefix}-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/api/health"
  }
}

resource "aws_lb_listener" "grafana" {
  load_balancer_arn = var.alb_arn
  port              = 3000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.name_prefix}-grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.observability_execution.arn

  container_definitions = jsonencode([
    {
      name       = "grafana"
      image      = "grafana/grafana:11.2.0"
      essential  = true
      entryPoint = ["sh", "-c"]
      command = [
        "mkdir -p /etc/grafana/provisioning/datasources && echo \"$GRAFANA_DATASOURCES\" > /etc/grafana/provisioning/datasources/datasources.yaml && exec /run.sh"
      ]
      environment = [
        { name = "GRAFANA_DATASOURCES", value = local.grafana_datasources },
      ]
      secrets = [
        { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = aws_secretsmanager_secret.grafana_admin.arn },
      ]
      portMappings = [{ containerPort = 3000, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.observability["grafana"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "grafana" {
  name            = "grafana"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [var.ecs_tasks_sg_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.grafana]
}
