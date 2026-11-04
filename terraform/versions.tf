terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }

  # BACKEND PENDIENTE:
  # La configuración remota se define en backend.tf cuando el bootstrap
  # de estado sea aprobado. En Etapa 2 no se configura backend remoto.
}
