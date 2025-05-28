
resource "aws_iam_role" "eventbridge_ecs_scheduled_task_role" {
  name = "EventBridgeEcsScheduledTaskRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_ecs_scheduled_task_role_policy_attachment" {
  role       = aws_iam_role.eventbridge_ecs_scheduled_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceEventsRole"
}

resource "aws_scheduler_schedule" "this" {
  name                         = "ecs-scheduled-task-example"
  schedule_expression_timezone = "Asia/Tokyo"
  schedule_expression          = "cron(1 * * * ? *)"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = aws_ecs_cluster.this.arn
    role_arn = aws_iam_role.eventbridge_ecs_scheduled_task_role.arn
    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.this.arn
      task_count          = 1
      launch_type         = "FARGATE"
      network_configuration {
        subnets          = [aws_subnet.this.id]
        security_groups  = [aws_security_group.this.id]
        assign_public_ip = true
      }
    }
  }
}
