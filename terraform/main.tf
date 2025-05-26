data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_ecr_repository" "this" {
  name                 = "scheduled-task-example"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

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
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  cpu                      = "256"
  memory                   = "1024"
  container_definitions = jsonencode([
    {
      name      = "scheduled-task-example-1"
      image     = "scheduled-task-example:latest"
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

# NOTE: https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/task-iam-roles.html#create_task_iam_policy_and_role
data "aws_iam_policy_document" "ecs_task_execution_role_policy_document" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values = [
        data.aws_caller_identity.current.account_id
      ]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "EcsScheduledTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role_policy_document.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "EcsScheduledTaskRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# NOTE: https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/task-iam-roles.html#ecs-exec-required-iam-permissions
data "aws_iam_policy_document" "ecs_task_policy_document" {
  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "ecs_task_policy" {
  name   = "EcsScheduledTaskPolicy"
  policy = data.aws_iam_policy_document.ecs_task_policy_document.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "ecs-scheduled-task-example"
  retention_in_days = 7
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "this" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "${data.aws_region.current.name}a"
}

resource "aws_security_group" "this" {
  name   = "ecs-scheduled-task-example"
  vpc_id = aws_vpc.this.id
}

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
