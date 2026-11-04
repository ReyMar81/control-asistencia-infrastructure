# AWS CloudFormation

## 1. Responsabilidad

La implementación de CloudFormation describe la misma arquitectura que Terraform y Pulumi, pero de forma independiente:

- VPC y subredes públicas.
- Internet Gateway y rutas.
- Security Groups.
- Roles IAM e instance profiles.
- Dos instancias EC2 Amazon Linux 2023.
- User-data generado desde las plantillas YAML compartidas de Cloud-Init.
- Outputs equivalentes.

La Etapa 3D implementa la plantilla. No se ha creado ningún stack ni se ha ejecutado un despliegue.

## 2. Archivos

| Archivo | Propósito |
| --- | --- |
| `template.yaml` | Plantilla generada con todos los recursos |
| `template.yaml.tmpl` | Fuente con marcadores para user-data |
| `parameters.dev.json.example` | Parámetros de ejemplo, sin secretos |
| `../scripts/render-cloudformation.py` | Genera user-data desde Cloud-Init compartido |
| `README.md` | Instrucciones y estado de la etapa |

## 3. Parámetros previstos

| Parámetro | Descripción | Ejemplo |
| --- | --- | --- |
| `ProjectName` | Prefijo de recursos | `control-asistencia` |
| `Environment` | Entorno | `dev` |
| `VpcCidr` | CIDR de VPC | `10.10.0.0/16` |
| `PublicSubnetCidr` | CIDR de subnet pública | `10.10.1.0/24` |
| `AmiId` | AMI AL2023 x86_64 | Dynamic reference de SSM |
| `InstanceType` | Tipo de instancia | `t3.micro` |
| `GitBranch` | Rama de aplicación | `main` |
| `DbPassword` / `JwtSecret` | Secretos de aplicación | Parámetros `NoEcho` |
| `ClientUrl` | Origen CORS | `http://localhost:5173` |

La plantilla no incluye una condición de bloqueo: una futura ejecución autorizada creará los recursos definidos. Los secretos se reciben como parámetros `NoEcho` y no tienen valores reales en Git.

## 4. Convenciones

- No usar la VPC por defecto.
- No abrir SSH.
- No usar key pairs.
- IMDSv2 obligatorio.
- Instance profiles obligatorios.
- El SG del backend referencia el SG del frontend.
- PostgreSQL sin reglas de entrada de red.
- Cloud-Init compartido desde las plantillas locales mediante `scripts/render-cloudformation.py`.
- Tags consistentes con Terraform y Pulumi.
- Sin secretos en parámetros, plantilla ni outputs.
- No usar `CAPABILITY_NAMED_IAM` sin revisión.

## 5. Flujo previsto

1. Validar la plantilla con `cfn-lint` o `aws cloudformation validate-template` en un entorno autorizado.
2. Crear un change set.
3. Revisar el change set y los costos.
4. Ejecutar el stack solo con autorización explícita.
5. Verificar SSM, Cloud-Init y salud de la aplicación.
6. Registrar outputs y versión del bundle.

La Etapa 3D ejecuta solo validaciones locales; no ejecuta creación de change sets ni despliegues.

## 6. Riesgos

- Un stack accidental puede crear recursos con costo.
- Los parámetros deben apuntar a la cuenta, región y AMI correctas.
- La IP pública dinámica puede cambiar.
- La destrucción del stack puede eliminar PostgreSQL sin respaldo.
- El uso de `CAPABILITY_NAMED_IAM` puede crear roles con nombres sensibles.
- El archivo generado debe regenerarse si cambian las plantillas Cloud-Init.

## 7. Estado de la Etapa 3D

- Recursos de red, seguridad, IAM y cómputo definidos.
- User-data frontend/backend generada desde Cloud-Init compartido.
- Sin stacks.
- Sin change sets.
- Sin cambios en AWS.
