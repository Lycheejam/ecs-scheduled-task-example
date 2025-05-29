resource "aws_ecr_repository" "this" {
  name                 = "scheduled-task-example"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
