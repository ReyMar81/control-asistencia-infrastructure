# Diseño de OIDC, buckets y estado

## 1. Estado de esta etapa

Este documento describe el bootstrap previsto. No se han creado recursos AWS, buckets, tablas, roles ni proveedores OIDC.

## 2. Proveedor OIDC de GitHub

### Configuración prevista

| Elemento | Valor |
| --- | --- |
| URL del proveedor | `https://token.actions.githubusercontent.com` |
| Audiencia | `sts.amazonaws.com` |
| Acción permitida | `sts:AssumeRoleWithWebIdentity` |

### Restricciones de confianza

El rol debe restringir la condición `sub` a un repositorio, rama y entorno específicos. Ejemplos de patrón, sin valores reales:

```text
repo:ORG/REPO:ref:refs/heads/main
repo:ORG/REPO:environment:production
```

No se debe usar un comodín que permita cualquier repositorio de GitHub.

### Roles previstos

| Rol | Propósito |
| --- | --- |
| `control-asistencia-terraform-plan` | Plan de Terraform |
| `control-asistencia-terraform-apply` | Aplicación aprobada de Terraform |
| `control-asistencia-pulumi-preview` | Preview de Pulumi |
| `control-asistencia-pulumi-up` | Aplicación aprobada de Pulumi |
| `control-asistencia-cloudformation-validate` | Validación y change set |
| `control-asistencia-cloudformation-deploy` | Despliegue aprobado |
| `control-asistencia-deploy-frontend` | Despliegue de frontend |
| `control-asistencia-deploy-backend` | Despliegue de backend |

Los nombres son propuestos. La creación requiere una revisión de permisos y autorización.

## 3. Buckets previstos

### 3.1 Bundle de Cloud-Init

Nombre lógico:

```text
control-asistencia-cloud-init-<environment>
```

Requisitos:

- Bloqueo de acceso público.
- Versionado.
- Cifrado con SSE-S3 o KMS.
- Política que permita lectura solo a los roles de las instancias y a los roles de publicación.
- Prefijo por versión: `cloud-init/<version>/`.
- Checksum publicado junto con el bundle.

Contenido:

- Scripts y plantillas de Cloud-Init.
- Manifiesto de versión.
- Checksum.

No debe contener secretos ni artefactos de aplicación.

### 3.2 Artefactos de aplicación

Nombre lógico:

```text
control-asistencia-artifacts-<environment>
```

Requisitos:

- Bloqueo de acceso público.
- Versionado.
- Cifrado.
- Prefijos separados para frontend y backend.
- Retención definida.

Contendrá:

- Build del frontend.
- Build del backend.
- Manifiestos de versión.

### 3.3 Estado de Terraform

Nombre lógico:

```text
control-asistencia-tfstate-<environment>
```

Requisitos:

- Bloqueo de acceso público.
- Versionado.
- Cifrado.
- Acceso limitado a los roles de Terraform.
- Bucket dedicado, no compartido con otros proyectos.
- Tabla DynamoDB de bloqueo dedicada o con clave de estado exclusiva.

Clave prevista:

```text
control-asistencia/terraform.tfstate
```

No se debe reutilizar el bucket de estado de `terraform-stackoverflow-01` ni modificar sus objetos.

## 4. Políticas mínimas

### Lectura del bundle

Permitir solo:

- `s3:GetObject` sobre el prefijo de la versión autorizada.
- `s3:ListBucket` sobre el prefijo, si es necesario para el bootstrap.

No permitir escritura desde las instancias.

### Lectura de secretos

Permitir solo:

- `secretsmanager:GetSecretValue` sobre el ARN del secreto de aplicación.
- Nada de `secretsmanager:ListSecrets` ni permisos amplios.

### Estado de Terraform

Permitir solo:

- Operaciones necesarias de lectura/escritura sobre el bucket y la tabla de estado del proyecto.
- Nada de acceso a estados de otros proyectos.

## 5. Orden de creación previsto

1. Revisar y aprobar nombres, cuenta y región.
2. Crear proveedor OIDC.
3. Crear roles de CI/CD con confianza restringida.
4. Crear bucket de estado y tabla de bloqueo.
5. Crear bucket de artefactos.
6. Crear bucket de Cloud-Init.
7. Configurar políticas.
8. Validar que no haya acceso público.
9. Probar asunción de rol con OIDC.
10. Recién entonces implementar las alternativas IaC.

La Etapa 2 no ejecuta ninguno de estos pasos.

## 6. Riesgos

- Un bucket público expondría artefactos o scripts.
- Un rol OIDC con comodines permitiría despliegues no autorizados.
- Un estado compartido podría mezclar recursos de proyectos.
- Un error de nombre podría reutilizar un bucket existente.
- La creación de recursos genera costos.

## 7. Pendientes

- Confirmar nombres definitivos.
- Confirmar cuenta y región.
- Confirmar retención y cifrado.
- Confirmar si se usará KMS administrado por el cliente.
- Confirmar el mecanismo de disparo entre repositorios.
- Aprobar la creación de recursos.
