# ESQUELETO — Etapa 2.
#
# Secreto previsto en AWS Secrets Manager:
#   nombre: control-asistencia/backend
#   contenido JSON:
#     DATABASE_URL
#     JWT_SECRET
#     ADMIN_PASSWORD
#
# El valor no se declara en Terraform ni en este repositorio.
# La creación del secreto debe hacerse con un valor aprobado fuera de Git.
# Las instancias solo reciben permiso de lectura.
#
# No usar secretos en variables, outputs, tfvars ni state.
