resource "aws_ecr_repository" "order_service" {
  name                 = "${var.name_prefix}-order-service"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "requester_service" {
  name                 = "${var.name_prefix}-requester-service"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "order_service_migration" {
  name                 = "${var.name_prefix}-order-service-migration"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "order_service" {
  name        = "${var.name_prefix}-order-svc-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/py-order-service/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }
}

resource "aws_lb_target_group" "requester_service" {
  name        = "${var.name_prefix}-requester-svc-tg"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/jv-requester-service/actuator/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "order_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.order_service.arn
  }

  condition {
    path_pattern {
      values = ["/py-order-service/*"]
    }
  }
}

resource "aws_lb_listener_rule" "requester_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.requester_service.arn
  }

  condition {
    path_pattern {
      values = ["/jv-requester-service/*"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name = "${var.name_prefix}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "${var.name_prefix}-ecs-execution-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.order_db_secret_arn, var.requester_db_secret_arn]
    }]
  })
}

resource "aws_iam_role" "order_service_task" {
  name = "${var.name_prefix}-order-service-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "order_service_sns" {
  name = "${var.name_prefix}-order-service-sns-publish"
  role = aws_iam_role.order_service_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = [var.sns_topic_arn]
    }]
  })
}

resource "aws_iam_role" "requester_service_task" {
  name = "${var.name_prefix}-requester-service-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_cloudwatch_log_group" "order_service" {
  name              = "/ecs/${var.name_prefix}/order-service"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "requester_service" {
  name              = "/ecs/${var.name_prefix}/requester-service"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "order_service_migration" {
  name              = "/ecs/${var.name_prefix}/order-service-migration"
  retention_in_days = 14
}

locals {
  order_service_image           = var.order_service_image != "" ? var.order_service_image : "${aws_ecr_repository.order_service.repository_url}:latest"
  requester_service_image       = var.requester_service_image != "" ? var.requester_service_image : "${aws_ecr_repository.requester_service.repository_url}:latest"
  order_service_migration_image = "${aws_ecr_repository.order_service_migration.repository_url}:latest"
}

resource "aws_ecs_task_definition" "order_service" {
  family                   = "${var.name_prefix}-order-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.order_service_task.arn

  container_definitions = jsonencode([
    {
      name      = "order-service"
      image     = local.order_service_image
      essential = true
      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
      environment = [
        { name = "DB_HOST", value = var.order_db_endpoint },
        { name = "DB_NAME", value = "orders" },
        { name = "REQUESTER_SERVICE_URL", value = "http://requester-service.${var.service_discovery_namespace_name}:8081/jv-requester-service" },
        { name = "SNS_TOPIC_ARN", value = var.sns_topic_arn },
        { name = "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", value = var.otel_collector_endpoint },
        { name = "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", value = replace(var.otel_collector_endpoint, "/v1/traces", "/v1/metrics") },
      ]
      secrets = [
        { name = "DB_USER", valueFrom = "${var.order_db_secret_arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${var.order_db_secret_arn}:password::" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.order_service.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "order-service"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "order_service_migration" {
  family                   = "${var.name_prefix}-order-service-migration"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([
    {
      name      = "order-service-migration"
      image     = local.order_service_migration_image
      essential = true
      command   = ["update"]
      environment = [
        { name = "LIQUIBASE_COMMAND_URL", value = "jdbc:postgresql://${var.order_db_endpoint}:5432/orders" },
        { name = "LIQUIBASE_COMMAND_CHANGELOG_FILE", value = "changelog/db.changelog-master.yaml" },
      ]
      secrets = [
        { name = "LIQUIBASE_COMMAND_USERNAME", valueFrom = "${var.order_db_secret_arn}:username::" },
        { name = "LIQUIBASE_COMMAND_PASSWORD", valueFrom = "${var.order_db_secret_arn}:password::" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.order_service_migration.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "order-service-migration"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "requester_service" {
  family                   = "${var.name_prefix}-requester-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.requester_service_task.arn

  container_definitions = jsonencode([
    {
      name      = "requester-service"
      image     = local.requester_service_image
      essential = true
      portMappings = [{ containerPort = 8081, protocol = "tcp" }]
      environment = [
        { name = "DB_HOST", value = var.requester_db_endpoint },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "requesters" },
        { name = "OTLP_COLLECTOR_ENDPOINT", value = var.otel_collector_endpoint },
      ]
      secrets = [
        { name = "DB_USER", valueFrom = "${var.requester_db_secret_arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${var.requester_db_secret_arn}:password::" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.requester_service.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "requester-service"
        }
      }
    }
  ])
}

resource "aws_service_discovery_service" "order_service" {
  name = "order-service"

  dns_config {
    namespace_id = var.service_discovery_namespace_id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_service_discovery_service" "requester_service" {
  name = "requester-service"

  dns_config {
    namespace_id = var.service_discovery_namespace_id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_service" "order_service" {
  name            = "order-service"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.order_service.arn
  desired_count   = var.order_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [var.ecs_tasks_sg_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.order_service.arn
    container_name   = "order-service"
    container_port   = 8000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.order_service.arn
  }

  depends_on = [aws_lb_listener_rule.order_service]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_service" "requester_service" {
  name                              = "requester-service"
  cluster                           = var.ecs_cluster_id
  task_definition                   = aws_ecs_task_definition.requester_service.arn
  desired_count                     = var.requester_service_desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [var.ecs_tasks_sg_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.requester_service.arn
    container_name   = "requester-service"
    container_port   = 8081
  }

  service_registries {
    registry_arn = aws_service_discovery_service.requester_service.arn
  }

  depends_on = [aws_lb_listener_rule.requester_service]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ---------------------------------------------------------------------------
# Application Auto Scaling (target tracking por CPU)
# ---------------------------------------------------------------------------

locals {
  ecs_cluster_name = element(split("/", var.ecs_cluster_id), 1)
}

resource "aws_appautoscaling_target" "order_service" {
  service_namespace  = "ecs"
  resource_id        = "service/${local.ecs_cluster_name}/${aws_ecs_service.order_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.order_service_min_capacity
  max_capacity       = var.order_service_max_capacity
}

resource "aws_appautoscaling_policy" "order_service_cpu" {
  name               = "${var.name_prefix}-order-service-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.order_service.resource_id
  scalable_dimension = aws_appautoscaling_target.order_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.order_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.order_service_cpu_target_value
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_target" "requester_service" {
  service_namespace  = "ecs"
  resource_id        = "service/${local.ecs_cluster_name}/${aws_ecs_service.requester_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.requester_service_min_capacity
  max_capacity       = var.requester_service_max_capacity
}

resource "aws_appautoscaling_policy" "requester_service_cpu" {
  name               = "${var.name_prefix}-requester-service-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.requester_service.resource_id
  scalable_dimension = aws_appautoscaling_target.requester_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.requester_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.requester_service_cpu_target_value
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}
