# Backend remoto previsto.
#
# No se activa en la Etapa 2 porque requiere un bucket S3 y una tabla
# DynamoDB dedicados que todavía no han sido aprobados ni creados.
#
# terraform {
#   backend "s3" {
#     bucket         = "control-asistencia-tfstate-dev"
#     key            = "control-asistencia/terraform.tfstate"
#     region         = "us-east-2"
#     dynamodb_table = "control-asistencia-tfstate-locks"
#     encrypt        = true
#   }
# }
#
# No reutilizar el bucket ni la tabla de estado de terraform-stackoverflow-01.
