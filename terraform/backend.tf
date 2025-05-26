terraform {
  backend "s3" {
    bucket = "your-bucket"
    key    = "ecs-scheduled-task-example/terraform.tfstate"
    region = "ap-northeast-1"
  }
}
