# Security Group para la instancia Frontend
# Expone HTTP (80) y HTTPS (443) a Internet para servir la SPA y el proxy API
resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-frontend-sg"
  description = "Permite acceso web publico (HTTP/HTTPS) a la instancia Frontend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP desde Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS desde Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida total para SSM, S3, Git y comunicacion con Backend"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-frontend-sg"
  }
}

# Security Group para la instancia Backend
# Solo permite tráfico TCP en el puerto 3000 proveniente del Security Group del Frontend
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend-sg"
  description = "Permite trafico API TCP 3000 unicamente desde el Security Group del Frontend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Acceso API TCP 3000 exclusivo desde Frontend SG"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  egress {
    description = "Salida total a Internet para SSM, Git, DNF y repositorios"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-backend-sg"
  }
}
