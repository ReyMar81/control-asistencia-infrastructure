# Consulta dinamica de la AMI oficial mas reciente de Amazon Linux 2023 x86_64
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  selected_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023.id
}

# ==============================================================================
# Instancia EC2: Backend + PostgreSQL
# ==============================================================================
resource "aws_instance" "backend" {
  ami                         = local.selected_ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.backend.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens   = "required" # IMDSv2 obligatorio
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Renderizado de la plantilla Cloud-Init YAML para Backend
  user_data = templatefile("${path.module}/../cloud-init/user-data/backend.yaml.tmpl", {
    BACKEND_REPO_URL = var.backend_repo_url
    GIT_BRANCH       = var.git_branch
    DB_USER          = var.db_user
    DB_PASSWORD      = var.db_password
    DB_NAME          = var.db_name
    JWT_SECRET       = var.jwt_secret
    CLIENT_URL       = var.client_url
    PORT             = tostring(var.backend_port)
  })

  tags = {
    Name = "${var.project_name}-backend"
  }
}

# ==============================================================================
# Instancia EC2: Frontend (SPA + Nginx Proxy)
# ==============================================================================
resource "aws_instance" "frontend" {
  ami                         = local.selected_ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens   = "required" # IMDSv2 obligatorio
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Renderizado de la plantilla Cloud-Init YAML para Frontend
  # Recibe la IP privada del backend para configurar el proxy inverso en Nginx
  user_data = templatefile("${path.module}/../cloud-init/user-data/frontend.yaml.tmpl", {
    FRONTEND_REPO_URL  = var.frontend_repo_url
    GIT_BRANCH         = var.git_branch
    BACKEND_PRIVATE_IP = aws_instance.backend.private_ip
  })

  tags = {
    Name = "${var.project_name}-frontend"
  }
}
