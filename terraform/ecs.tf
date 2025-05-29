resource "aws_ecs_cluster" "this" {
  name = "ecs-scheduled-task-example"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = "scheduled-task-example"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  cpu                      = "256"
  memory                   = "1024"
  container_definitions = jsonencode([
    {
      name      = "scheduled-task-example-1"
      image     = "${aws_ecr_repository.this.repository_url}:latest"
      cpu       = 256
      memory    = 1024
      essential = true
      command   = ["sh", "-c", "echo 'Hello, ECS Scheduled Task!'"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "ecs-scheduled-task-example"
  retention_in_days = 7
}
