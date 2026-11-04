variable "aws_region" {
  description = "Región AWS del despliegue."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Prefijo para nombres de recursos y etiquetas."
  type        = string
  default     = "control-asistencia"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]+$", var.project_name))
    error_message = "project_name solo puede contener letras minúsculas, números y guiones."
  }
}

variable "environment" {
  description = "Entorno lógico (dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser dev, staging o prod."
  }
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC."
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr debe ser un bloque CIDR válido."
  }
}

variable "public_subnet_cidr" {
  description = "Bloque CIDR de la subred pública."
  type        = string
  default     = "10.10.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr))
    error_message = "public_subnet_cidr debe ser un bloque CIDR válido."
  }
}

variable "availability_zone" {
  description = "Zona de disponibilidad para la subred pública."
  type        = string
  default     = "us-east-2a"
}

variable "instance_type" {
  description = "Tipo de instancia EC2 para frontend y backend."
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "ID de AMI AL2023 x86_64. Si se deja vacía, se consulta dinámicamente la última versión oficial de Amazon."
  type        = string
  default     = ""

  validation {
    condition     = var.ami_id == "" || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id debe estar vacío o tener el formato ami-XXXXXXXX."
  }
}

variable "timezone" {
  description = "Zona horaria del sistema y PostgreSQL."
  type        = string
  default     = "America/La_Paz"
}

# Repositorios de aplicación para la demostración académica
variable "backend_repo_url" {
  description = "URL del repositorio Git de la aplicación Backend."
  type        = string
  default     = "https://github.com/ReyMar81/backend-control-asistencia.git"
}

variable "frontend_repo_url" {
  description = "URL del repositorio Git de la aplicación Frontend."
  type        = string
  default     = "https://github.com/ReyMar81/frontend-control-asistencia.git"
}

variable "git_branch" {
  description = "Rama de Git a clonar y desplegar en ambas instancias."
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.git_branch))
    error_message = "git_branch contiene caracteres no permitidos."
  }
}

# Configuración de base de datos y aplicación
variable "db_user" {
  description = "Usuario de la base de datos PostgreSQL."
  type        = string
  default     = "ca_app"
}

variable "db_password" {
  description = "Contraseña del usuario de la base de datos PostgreSQL."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 12 && !can(regex("[\\r\\n]", var.db_password))
    error_message = "db_password debe tener al menos 12 caracteres y no contener saltos de línea."
  }
}

variable "db_name" {
  description = "Nombre de la base de datos PostgreSQL."
  type        = string
  default     = "control_asistencia"
}

variable "jwt_secret" {
  description = "Clave secreta para firma de tokens JWT."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.jwt_secret) >= 32 && !can(regex("[\\r\\n]", var.jwt_secret))
    error_message = "jwt_secret debe tener al menos 32 caracteres y no contener saltos de línea."
  }
}

variable "client_url" {
  description = "URL permitida por CORS en el backend."
  type        = string
  default     = "http://localhost:5173"
}

variable "backend_port" {
  description = "Puerto TCP en el que escucha la API del backend."
  type        = number
  default     = 3000
}
