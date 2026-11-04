# Bootstrap de infraestructura

Este directorio documenta los recursos de soporte que deben existir antes de que las implementaciones de Terraform, Pulumi o CloudFormation puedan desplegar la arquitectura principal.

## Alcance

El bootstrap futuro incluye:

- Proveedor OIDC de GitHub en IAM.
- Roles IAM para GitHub Actions.
- Bucket S3 para el bundle de Cloud-Init.
- Bucket S3 para artefactos de aplicación.
- Bucket S3 y tabla DynamoDB para estado de Terraform.
- Políticas de mínimo privilegio.
- Configuración de cifrado, versionado y bloqueo de acceso público.

**Nada de esto se crea en la Etapa 2.**

## Principios

- No usar access keys estáticas.
- No reutilizar el bucket ni la tabla de estado de otros proyectos.
- No reutilizar el usuario IAM con `AdministratorAccess`.
- No crear recursos sin autorización.
- No incluir identificadores de cuenta ni valores reales en la documentación versionada.

## Documentos

- [`oidc-y-buckets.md`](oidc-y-buckets.md): diseño de OIDC, buckets y estado.
- [`../docs/07-ci-cd.md`](../docs/07-ci-cd.md): estrategia de workflows.
- [`../docs/09-seguridad.md`](../docs/09-seguridad.md): controles de seguridad.
