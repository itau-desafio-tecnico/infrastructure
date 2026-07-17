variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "ecs_tasks_sg_id" {
  type = string
}

variable "ecs_cluster_id" {
  type = string
}

variable "service_discovery_namespace_id" {
  type = string
}

variable "service_discovery_namespace_name" {
  type = string
}

variable "order_db_endpoint" {
  type = string
}

variable "requester_db_endpoint" {
  type = string
}

variable "order_db_secret_arn" {
  type = string
}

variable "requester_db_secret_arn" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}

variable "order_service_image" {
  type    = string
  default = ""
}

variable "requester_service_image" {
  type    = string
  default = ""
}

variable "order_service_desired_count" {
  type    = number
  default = 1
}

variable "requester_service_desired_count" {
  type    = number
  default = 1
}
