resource "aws_sns_topic" "order_created" {
  name = "${var.name_prefix}-order-created"
}

resource "aws_sqs_queue" "order_processing_dlq" {
  name                      = "${var.name_prefix}-order-processing-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "order_processing" {
  name                       = "${var.name_prefix}-order-processing"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_processing_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_policy" "order_processing" {
  queue_url = aws_sqs_queue.order_processing.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSnsPublish"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.order_processing.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.order_created.arn
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "order_processing" {
  topic_arn = aws_sns_topic.order_created.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.order_processing.arn
}
