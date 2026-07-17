output "sns_topic_arn" {
  value = aws_sns_topic.order_created.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.order_processing.id
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.order_processing.arn
}

output "sqs_dlq_url" {
  value = aws_sqs_queue.order_processing_dlq.id
}
