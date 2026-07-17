resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnets"
  }
}

resource "random_password" "order_db" {
  length  = 24
  special = false
}

resource "random_password" "requester_db" {
  length  = 24
  special = false
}

resource "aws_db_instance" "order" {
  identifier     = "${var.name_prefix}-order-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_encrypted     = true

  db_name  = "orders"
  username = "order_app"
  password = random_password.order_db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  multi_az                = false
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = {
    Name    = "${var.name_prefix}-order-db"
    Service = "order-service"
  }
}

resource "aws_db_instance" "requester" {
  identifier     = "${var.name_prefix}-requester-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_encrypted     = true

  db_name  = "requesters"
  username = "requester_app"
  password = random_password.requester_db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  multi_az                = false
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = {
    Name    = "${var.name_prefix}-requester-db"
    Service = "requester-service"
  }
}

resource "aws_secretsmanager_secret" "order_db" {
  name                    = "${var.name_prefix}/order-service/db"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "order_db" {
  secret_id = aws_secretsmanager_secret.order_db.id
  secret_string = jsonencode({
    host     = aws_db_instance.order.address
    port     = aws_db_instance.order.port
    dbname   = aws_db_instance.order.db_name
    username = aws_db_instance.order.username
    password = random_password.order_db.result
  })
}

resource "aws_secretsmanager_secret" "requester_db" {
  name                    = "${var.name_prefix}/requester-service/db"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "requester_db" {
  secret_id = aws_secretsmanager_secret.requester_db.id
  secret_string = jsonencode({
    host     = aws_db_instance.requester.address
    port     = aws_db_instance.requester.port
    dbname   = aws_db_instance.requester.db_name
    username = aws_db_instance.requester.username
    password = random_password.requester_db.result
  })
}
