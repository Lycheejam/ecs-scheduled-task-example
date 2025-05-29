data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_ecr_repository" "this" {
  name                 = "scheduled-task-example"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# TODO: 気が向いたらプライベートサブネット環境下でVPCエンドポイント使った方法も試す。

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

# NOTE: ECS実行ロールとECSが利用するECSロールの全体像
#       https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/security-iam-roles.html
# NOTE: ECS実行ロールの定義
#       https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/task_execution_IAM_role.html
data "aws_iam_policy_document" "ecs_task_execution" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "EcsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# NOTE: ECSタスクロールの定義
#       https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/task-iam-roles.html
data "aws_iam_policy_document" "ecs_task" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
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

resource "aws_iam_role" "ecs_task" {
  name = "EcsTaskRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task.json
}

# NOTE: ECSタスクロールにECS Exec のアクセス許可を追加
#       https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/task-iam-roles.html#ecs-exec-required-iam-permissions
data "aws_iam_policy_document" "ecs_task_with_ecs_exec" {
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

resource "aws_iam_policy" "ecs_task_with_ecs_exec" {
  name   = "EcsTaskWithEcsExecPolicy"
  policy = data.aws_iam_policy_document.ecs_task_with_ecs_exec.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_with_ecs_exec" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ecs_task_with_ecs_exec.arn
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "ecs-scheduled-task-example"
  retention_in_days = 7
}
