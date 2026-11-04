# Pulumi

## 1. Responsabilidad

La implementación de Pulumi describe la misma arquitectura que Terraform, pero de forma independiente:

- VPC y subredes públicas.
- Internet Gateway y rutas.
- Security Groups.
- Roles IAM e instance profiles.
- Dos instancias EC2 Amazon Linux 2023.
- User-data desde las plantillas YAML compartidas de Cloud-Init.
- Outputs equivalentes.

La Etapa 3C implementa los recursos. No se han creado recursos ni se ha ejecutado `pulumi up`.

## 2. Archivos

| Archivo | Propósito |
| --- | --- |
| `Pulumi.yaml` | Metadatos del proyecto |
| `Pulumi.dev.yaml.example` | Configuración de ejemplo, sin secretos |
| `package.json` | Dependencias y scripts |
| `tsconfig.json` | Configuración de TypeScript |
| `index.ts` | Punto de entrada del programa |
| `index.ts` | Red, seguridad, IAM, instancias y user-data |
| `package-lock.json` | Dependencias instaladas y bloqueadas |

## 3. Configuración prevista

| Clave | Descripción | Ejemplo |
| --- | --- | --- |
| `awsRegion` | Región AWS | `us-east-2` |
| `projectName` | Prefijo de recursos | `control-asistencia` |
| `environment` | Entorno | `dev` |
| `vpcCidr` | CIDR de VPC | `10.10.0.0/16` |
| `publicSubnetCidr` | CIDR de subnet pública | `10.10.1.0/24` |
| `availabilityZone` | Zona de disponibilidad | `us-east-2a` |
| `instanceType` | Tipo de instancia | `t3.micro` |
| `amiId` | AMI AL2023 x86_64 opcional | Vacío para consulta dinámica |
| `gitBranch` | Rama de aplicación | `main` |
| `dbPassword` / `jwtSecret` | Secretos de aplicación | Configuración secreta de Pulumi |

Los secretos se obtienen con `config.requireSecret`, se mantienen como Outputs secretos y no tienen valores por defecto en el código.

## 4. Estado

Pulumi utiliza un backend de estado. Antes de ejecutar Pulumi se debe definir y aprobar:

- Backend de estado.
- Nombre del stack.
- Separación entre stacks o entornos.
- Control de acceso.

No se debe reutilizar el estado de otro proyecto ni el stack de la prueba anterior.

Esta etapa no configura ni inicializa un backend remoto.

## 5. Convenciones

- No usar la VPC por defecto.
- No abrir SSH.
- No usar key pairs.
- IMDSv2 obligatorio.
- Instance profiles obligatorios.
- El SG del backend referencia el SG del frontend.
- PostgreSQL sin reglas de entrada de red.
- Cloud-Init compartido desde `cloud-init/user-data/*.yaml.tmpl`.
- Tags consistentes con Terraform y CloudFormation.
- Sin secretos en configuración, código ni outputs.

## 6. Flujo previsto

1. Configurar backend y stack.
2. Ejecutar `npm install` y compilación TypeScript.
3. Ejecutar `pulumi preview`.
4. Revisar el preview y el plan de cambios.
5. Ejecutar `pulumi up` solo con autorización explícita.
6. Verificar SSM, Cloud-Init y salud de la aplicación.
7. Registrar outputs y versión del bundle.

La validación local ejecuta instalación y compilación TypeScript, pero no `pulumi preview` ni `pulumi up`.

## 7. Riesgos

- El estado de Pulumi puede contener datos sensibles.
- Un `pulumi up` accidental puede crear recursos con costo.
- La configuración de región o stack puede no coincidir con la cuenta objetivo.
- La IP pública dinámica puede cambiar.
- La destrucción del backend puede eliminar PostgreSQL sin respaldo.
- La user-data contiene secretos de aplicación y el estado de Pulumi debe protegerse adecuadamente.

## 8. Estado de la Etapa 3C

- Red, Security Groups, IAM e instancias declarados.
- IP privada del backend interpolada en la plantilla del frontend.
- Sin backend de estado configurado.
- Sin `pulumi up`.
- Sin cambios en AWS.
