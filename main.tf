##############################################
# Minimal ECS Fargate deployment (no ALB, no NAT)
# Resources: VPC/subnet/SG, ECR, ECS Fargate, IAM roles, CloudWatch Logs
##############################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state management is required for a real deployment workflow.
  # Recommended backend: S3 for state storage + DynamoDB for state locking.
  # Example backend configuration:
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "go-version-app/terraform.tfstate"
    region         = "af-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "af-south-1" # change as needed; af-south-1 = Cape Town region
}

variable "app_name" {
  default = "go-version-app"
}

variable "app_version" {
  description = "Value passed to the app's VERSION env var"
  default     = "v1.0.0"
}

variable "container_port" {
  default = 3000
}

variable "image_tag" {
  description = "Immutable tag of an image pushed separately to the Terraform-managed ECR repository"
  type        = string

  validation {
    condition     = length(trimspace(var.image_tag)) > 0 && var.image_tag != "latest"
    error_message = "image_tag must be a non-empty immutable tag and must not be latest."
  }
}

##############################################
# 1. Networking: VPC, public subnet, IGW, route table, SG
##############################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.app_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.app_name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = { Name = "${var.app_name}-public-subnet" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.app_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "app" {
  name        = "${var.app_name}-sg"
  description = "Allow inbound app traffic on ${var.container_port}"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "App port"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # restrict to your IP range for tighter security
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-sg" }
}

##############################################
# 2. ECR repository
##############################################

resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.app_name}-ecr" }
}

##############################################
# 3. IAM roles: task execution role + task role
##############################################

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: lets ECS pull image from ECR and write logs
resource "aws_iam_role" "execution_role" {
  name               = "${var.app_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: permissions the app itself needs at runtime (none required here,
# kept minimal/empty since the app makes no AWS API calls)
resource "aws_iam_role" "task_role" {
  name               = "${var.app_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

##############################################
# 4. CloudWatch Logs
##############################################

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 7 # short retention keeps cost minimal
}

##############################################
# 5. ECS cluster, task definition, service (Fargate)
##############################################

resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256" # 0.25 vCPU - smallest Fargate size
  memory                   = "512" # 0.5 GB - smallest Fargate size
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = var.app_name
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "VERSION"
          value = var.app_version
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1 # single task; raise if you need availability during deploys
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true # no NAT Gateway / no ALB needed
  }
}

##############################################
# Outputs
##############################################

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "note_public_ip" {
  value = "Fargate tasks with assign_public_ip=true get an ephemeral public IP on each restart. Retrieve it via: aws ecs list-tasks --cluster ${var.app_name}-cluster --service-name ${var.app_name}-service, then aws ecs describe-tasks / describe-network-interfaces. For a stable address, add an ALB or Elastic IP + NLB later."
}
