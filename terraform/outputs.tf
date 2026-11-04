output "aws_region" {
  description = "Región configurada."
  value       = var.aws_region
}

output "project_name" {
  description = "Nombre del proyecto."
  value       = var.project_name
}

output "environment" {
  description = "Entorno lógico."
  value       = var.environment
}

output "vpc_cidr" {
  description = "CIDR previsto para la VPC."
  value       = var.vpc_cidr
}

output "vpc_id" {
  description = "ID de la VPC creada."
  value       = aws_vpc.main.id
}

output "frontend_instance_id" {
  description = "ID de la instancia EC2 frontend."
  value       = aws_instance.frontend.id
}

output "frontend_public_ip" {
  description = "IP pública dinámica del frontend."
  value       = aws_instance.frontend.public_ip
}

output "frontend_private_ip" {
  description = "IP privada del frontend."
  value       = aws_instance.frontend.private_ip
}

output "backend_instance_id" {
  description = "ID de la instancia EC2 backend."
  value       = aws_instance.backend.id
}

output "backend_public_ip" {
  description = "IP pública dinámica del backend."
  value       = aws_instance.backend.public_ip
}

output "backend_private_ip" {
  description = "IP privada del backend."
  value       = aws_instance.backend.private_ip
}

output "frontend_security_group_id" {
  description = "ID del Security Group del frontend."
  value       = aws_security_group.frontend.id
}

output "backend_security_group_id" {
  description = "ID del Security Group del backend."
  value       = aws_security_group.backend.id
}

output "application_url" {
  description = "URL HTTP de acceso a la aplicación frontend."
  value       = "http://${aws_instance.frontend.public_ip}"
}
