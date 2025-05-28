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
      # TODO: fargateの場合、諸々VPCエンドポイントを置かないといけないらしい。また明日。
      # https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/vpc-endpoints.html
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
