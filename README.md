# Control de Asistencia — Infraestructura AWS

Repositorio de infraestructura como código para desplegar la aplicación **Control de Asistencia** en AWS.

Este repositorio contiene la organización, documentación y alternativas de IaC del proyecto. Las implementaciones se validan localmente y no deben desplegarse sin autorización explícita.

## Propósito

- Definir la arquitectura de referencia en AWS para frontend, backend y PostgreSQL.
- Mantener una única fuente de verdad para los scripts de Cloud-Init.
- Preparar implementaciones independientes en Terraform, Pulumi y AWS CloudFormation.
- Documentar seguridad, operación, CI/CD y recuperación antes de desplegar.
- Evitar credenciales, secretos y datos sensibles dentro del repositorio.

## Repositorios relacionados

| Componente | Repositorio |
| --- | --- |
| Backend + PostgreSQL | https://github.com/ReyMar81/backend-control-asistencia.git |
| Frontend | https://github.com/ReyMar81/frontend-control-asistencia.git |
| Infraestructura | Este repositorio |

El backend utiliza Node.js, Express y PostgreSQL. El frontend utiliza React y Vite.

## Arquitectura general

La arquitectura de referencia utiliza dos instancias Amazon Linux 2023 x86_64 en `us-east-2`:

- **EC2 frontend:** subred pública, Nginx, IP pública dinámica, sin SSH.
- **EC2 backend-db:** subred pública con IP pública dinámica para salida a Internet, Express en el puerto 3000 y PostgreSQL escuchando únicamente en `localhost:5432`.
- **Security Groups:** el puerto 3000 del backend solo acepta tráfico desde el Security Group del frontend.
- **Administración:** AWS Systems Manager Session Manager, sin puerto 22 expuesto.
- **Secretos:** AWS Secrets Manager, sin valores en Git.
- **Cloud-Init:** bundle versionado en S3, con checksum, consumido por las tres alternativas de IaC.

La IP pública del backend se utiliza para evitar el costo de un NAT Gateway. No implica que la API sea públicamente accesible: el Security Group restringe la entrada al puerto 3000. Nginx accede al backend mediante su IP privada dentro de la VPC.

El detalle completo, incluido el diagrama Mermaid y la separación entre tráfico de aplicación y administración, está en [`docs/01-arquitectura.md`](docs/01-arquitectura.md).

## Alternativas de IaC

El repositorio contiene tres implementaciones independientes:

1. **Terraform** — [`terraform/`](terraform/)
2. **Pulumi** — [`pulumi/`](pulumi/)
3. **AWS CloudFormation** — [`cloudformation/`](cloudformation/)

Las tres consumen el mismo bundle de Cloud-Init definido en [`cloud-init/`](cloud-init/).

> **Importante:** Terraform, Pulumi y CloudFormation son alternativas excluyentes para el mismo entorno. No deben desplegarse simultáneamente sobre los mismos recursos ni compartir nombres, VPC, Security Groups o instancias. Cada alternativa utiliza un rango de red propio para reducir el riesgo de colisión accidental.

## Cloud-Init compartido

La fuente única de verdad se encuentra en [`cloud-init/`](cloud-init/). El flujo previsto es:

1. Los scripts y plantillas se empaquetan en un bundle versionado.
2. El bundle se publica en S3 con un checksum SHA-256.
3. Cada implementación IaC pasa a la instancia el bucket, la clave, la versión y el checksum.
4. Cloud-Init descarga el bundle, verifica su integridad y ejecuta el rol `frontend` o `backend-db`.

En esta etapa no se implementa la publicación ni la ejecución funcional. Ver [`docs/03-cloud-init.md`](docs/03-cloud-init.md).

## Requisitos previos

- Cuenta AWS con permisos mínimos para desplegar los recursos de cada alternativa.
- Región `us-east-2`.
- AMI de Amazon Linux 2023 x86_64.
- Acceso a AWS Secrets Manager.
- Un bucket S3 para el bundle de Cloud-Init.
- Roles IAM para las instancias y para CI/CD mediante OIDC.
- Terraform, Pulumi o AWS CLI según la alternativa que se vaya a utilizar.
- Acceso a los repositorios de backend y frontend para el flujo de CI/CD.

No se requieren ni se deben configurar access keys estáticas de AWS en este repositorio.

## Estado actual

**Etapa 3D — Terraform, Pulumi y CloudFormation implementados y validados localmente.**

- Estructura de directorios creada.
- Documentación técnica inicial redactada.
- Terraform implementado para la arquitectura académica de dos instancias y Cloud-Init YAML compartido.
- Pulumi y CloudFormation implementados como alternativas independientes con paridad arquitectónica.
- Esqueletos de workflows de GitHub Actions creados.
- Scripts de Cloud-Init y despliegue marcados como no implementados.
- Sin cambios en AWS.
- Sin cambios en los repositorios de aplicación.
- Sin acceso a los proyectos Terraform/OpenTofu anteriores.

Los scripts funcionales de Cloud-Init, las implementaciones IaC completas, la publicación del bundle y los despliegues corresponden a etapas posteriores.

## Etapas de implementación

1. Auditoría técnica y de seguridad.
2. Estructura del repositorio y documentación base. **(actual)**
3. Cloud-Init compartido y validaciones.
4. Implementación de Terraform.
5. Implementación de Pulumi.
6. Implementación de CloudFormation.
7. CI/CD con GitHub Actions y OIDC.
8. Despliegue integral y pruebas.
9. Operación, respaldo y documentación final.

No se debe avanzar a la Etapa 3 sin revisión y autorización.

## Documentación

| Documento | Contenido |
| --- | --- |
| [`docs/01-arquitectura.md`](docs/01-arquitectura.md) | Arquitectura, decisiones, diagrama y flujos |
| [`docs/02-auditoria.md`](docs/02-auditoria.md) | Hallazgos de auditoría y riesgos heredados |
| [`docs/03-cloud-init.md`](docs/03-cloud-init.md) | Contratos, bundle, roles y ciclo de vida |
| [`docs/04-terraform.md`](docs/04-terraform.md) | Responsabilidades y convenciones de Terraform |
| [`docs/05-pulumi.md`](docs/05-pulumi.md) | Responsabilidades y convenciones de Pulumi |
| [`docs/06-cloudformation.md`](docs/06-cloudformation.md) | Responsabilidades y convenciones de CloudFormation |
| [`docs/07-ci-cd.md`](docs/07-ci-cd.md) | OIDC, workflows y estrategia de despliegue |
| [`docs/08-operacion-y-runbook.md`](docs/08-operacion-y-runbook.md) | Operación, respaldo, recuperación y cambios |
| [`docs/09-seguridad.md`](docs/09-seguridad.md) | Controles, riesgos y limitaciones |
| [`docs/10-troubleshooting.md`](docs/10-troubleshooting.md) | Diagnóstico de fallos frecuentes |

## Advertencia

Las implementaciones de IaC no deben desplegarse todavía sin autorización. Pulumi fue compilado localmente en la Etapa 3C; no se han creado recursos AWS.

Tampoco se deben reutilizar las credenciales, instancias, Security Groups, key pairs ni estados remotos de los proyectos anteriores. Consulta [`SECURITY.md`](SECURITY.md) y [`docs/02-auditoria.md`](docs/02-auditoria.md).
