# Terraform

## 1. Responsabilidad

La implementación de Terraform crea, de forma independiente, la arquitectura de referencia:

- VPC y subredes públicas.
- Internet Gateway y route table.
- Security Groups.
- Roles IAM e instance profiles.
- Dos instancias EC2 Amazon Linux 2023.
- User-data renderizada directamente desde las plantillas YAML compartidas de Cloud-Init.
- Outputs para IPs, DNS, IDs y parámetros operativos.

La Etapa 3B deja la configuración lista para una futura ejecución controlada. No se ejecuta `terraform apply`.

## 2. Archivos

| Archivo | Propósito |
| --- | --- |
| `versions.tf` | Versión de Terraform y providers |
| `providers.tf` | Provider AWS y tags por defecto |
| `backend.tf` | Configuración prevista del estado remoto |
| `variables.tf` | Entradas del módulo |
| `network.tf` | VPC, subredes, IGW y rutas |
| `security.tf` | Security Groups y reglas |
| `iam.tf` | Roles, políticas e instance profiles |
| `compute.tf` | AMI, instancias y user-data |
| `outputs.tf` | Salidas |
| `terraform.tfvars.example` | Ejemplo sin secretos |
| `.terraform.lock.hcl` | Versión de provider fijada por `terraform init` |

## 3. Entradas implementadas

| Variable | Descripción | Valor de ejemplo |
| --- | --- | --- |
| `aws_region` | Región AWS | `us-east-2` |
| `project_name` | Prefijo de recursos | `control-asistencia` |
| `environment` | Entorno | `dev` |
| `vpc_cidr` | CIDR de VPC | `10.10.0.0/16` |
| `public_subnet_cidr` | CIDR de la subred pública | `10.10.1.0/24` |
| `availability_zone` | Zona de disponibilidad | `us-east-2a` |
| `ami_id` | AMI AL2023 x86_64 opcional | Vacío para consulta dinámica |
| `instance_type` | Tipo de instancia | `t3.micro` |
| `timezone` | Zona horaria | `America/La_Paz` |
| `backend_repo_url` / `frontend_repo_url` | Repositorios de aplicación | URLs oficiales del proyecto |
| `git_branch` | Rama a clonar | `main` |
| `db_user` / `db_name` / `backend_port` | Configuración del backend | `ca_app` / `control_asistencia` / `3000` |
| `db_password` / `jwt_secret` | Secretos sensibles para Cloud-Init | Sin valor por defecto |

Las credenciales AWS no se definen en Terraform. Los secretos de aplicación deben proporcionarse desde un archivo tfvars local no versionado o variables de entorno; al formar parte del user-data, también quedarán en el estado de Terraform.

## 4. Salidas previstas

| Salida | Descripción |
| --- | --- |
| `vpc_id` | ID de la VPC |
| `frontend_instance_id` | ID de la instancia frontend |
| `frontend_public_ip` | IP pública dinámica del frontend |
| `frontend_private_ip` | IP privada del frontend |
| `backend_instance_id` | ID de la instancia backend |
| `backend_private_ip` | IP privada del backend |
| `backend_public_ip` | IP pública dinámica del backend |
| `frontend_security_group_id` | SG del frontend |
| `backend_security_group_id` | SG del backend |
| `application_url` | URL HTTP construida con la IP pública del frontend |

Las IPs públicas son dinámicas. No deben tratarse como nombres estables ni usarse para configuración interna.

## 5. Estado remoto

El estado remoto previsto debe ser exclusivo para este proyecto. No se debe reutilizar el estado de `terraform-stackoverflow-01` ni sobrescribir sus claves.

La configuración prevista es:

- Bucket S3 dedicado, con versionado, cifrado y acceso público bloqueado.
- Tabla DynamoDB para bloqueo de estado.
- Clave de estado propia, por ejemplo `control-asistencia/terraform.tfstate`.
- Backend configurado antes de ejecutar `terraform init` con backend remoto.

`backend.tf` contiene un bloque comentado porque la Etapa 2 no crea buckets ni tablas. La creación del backend forma parte del bootstrap de infraestructura y requiere autorización.

No se deben usar credenciales estáticas en el backend. El acceso debe realizarse mediante roles y OIDC en CI/CD, o mediante credenciales temporales de un operador autorizado.

## 6. Convenciones

- Todos los recursos deben llevar `Project`, `Environment` y `ManagedBy` en tags.
- No usar la VPC por defecto.
- No abrir SSH.
- No usar key pairs.
- IMDSv2 obligatorio.
- Las instancias deben tener instance profile.
- El SG del backend debe referenciar el SG del frontend, no un CIDR amplio.
- PostgreSQL no debe tener reglas de Security Group de entrada.
- La user-data se obtiene de las plantillas YAML versionadas del repositorio.
- No incluir secretos en archivos versionados ni outputs.

## 7. Flujo previsto

1. Configurar backend remoto y credenciales temporales.
2. Ejecutar `terraform fmt -check` y `terraform validate`.
3. Ejecutar `terraform plan` con aprobación manual.
4. Revisar el plan.
5. Ejecutar `terraform apply` solo con autorización explícita.
6. Verificar SSM, Cloud-Init y salud de la aplicación.
7. Registrar outputs y versión del bundle.

Esta etapa solo ejecuta validaciones locales; no ejecuta los pasos 3, 5 ni 6.

## 8. Riesgos

- El estado puede contener datos sensibles; debe protegerse.
- Un `apply` accidental puede crear recursos con costo.
- La AMI cambia con el tiempo; debe seleccionarse de forma controlada.
- La IP pública dinámica puede cambiar.
- La ausencia de NAT obliga a que ambas instancias tengan salida pública.
- La destrucción de la instancia backend puede eliminar PostgreSQL si no hay snapshot.

## 9. Estado de la Etapa 3B

- Recursos de red, seguridad, IAM e instancias declarados.
- Plantillas Cloud-Init YAML conectadas mediante `templatefile()`.
- Sin backend remoto configurado.
- Sin `terraform apply`.
- Sin cambios en AWS.
