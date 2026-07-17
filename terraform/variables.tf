variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "sa-east-1"
}

variable "environment" {
  description = "Name of the environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "order_service_image" {
  description = "URI of the Docker image for the order-service (e.g., <ecr>/order-service:tag). Leave empty for the first apply and update via CI/CD."
  type        = string
  default     = ""
}

variable "requester_service_image" {
  description = "URI of the Docker image for the requester-service (e.g., <ecr>/requester-service:tag). Leave empty for the first apply and update via CI/CD."
  type        = string
  default     = ""
}

variable "order_service_desired_count" {
  type    = number
  default = 1
}

variable "requester_service_desired_count" {
  type    = number
  default = 1
}

variable "db_instance_class" {
  description = "Class of the RDS instance"
  type        = string
  default     = "db.t4g.micro"
}
