# CI/CD

## 1. Objetivo

Implementar la actualización de las aplicaciones mediante GitHub Actions, OIDC, SSM Run Command y los scripts de actualización instalados por Cloud-Init.

## 2. Principios

- GitHub Actions con OIDC, sin access keys estáticas de AWS.
- Roles IAM de corta duración y mínimo privilegio.
- Separación entre validación, planificación y despliegue.
- Aprobación manual para operaciones que modifican AWS.
- Workflows de aplicación sin permisos de infraestructura.
- Workflows de infraestructura sin permisos para modificar los repositorios de aplicación.
- Ningún secreto en el repositorio ni en los logs.

## 3. Workflows de infraestructura

| Workflow | Propósito | Estado |
| --- | --- | --- |
| `terraform-plan.yml` | Formato, validación y plan | Esqueleto |
| `terraform-apply.yml` | Aplicación aprobada de Terraform | Esqueleto |
| `pulumi-preview.yml` | Compilación y preview de Pulumi | Esqueleto |
| `pulumi-up.yml` | Aplicación aprobada de Pulumi | Esqueleto |
| `cloudformation-validate.yml` | Validación y change set | Esqueleto |
| `cloudformation-deploy.yml` | Despliegue aprobado de CloudFormation | Esqueleto |

Los workflows de `apply`, `up` y `deploy` deben:

- Usar `workflow_dispatch`.
- Requerir un entorno protegido de GitHub.
- Requerir confirmación explícita.
- Tener permisos `id-token: write` y `contents: read`.
- Asumir un rol IAM específico.
- No ejecutarse en cada push.

## 4. Workflows de aplicación

| Workflow | Propósito | Estado |
| --- | --- | --- |
| `frontend-control-asistencia/.github/workflows/deploy.yml` | Actualización exclusiva del frontend por SSM | Implementado |
| `backend-control-asistencia/.github/workflows/deploy.yml` | Actualización exclusiva del backend por SSM | Implementado |

Los workflows se ejecutan en `push` a `main` y también permiten una ejecución manual:

- Cada repositorio obtiene credenciales temporales con `aws-actions/configure-aws-credentials@v4`.
- `AWS_DEPLOY_ROLE_ARN` y `SSM_INSTANCE_ID` se configuran como variables del entorno protegido `deploy-frontend` o `deploy-backend`.
- El workflow descarga los scripts comunes desde `ReyMar81/control-asistencia-infrastructure`.
- `concurrency` impide actualizaciones simultáneas del mismo componente.

## 5. OIDC

El proveedor OIDC de GitHub debe confiar en:

```text
token.actions.githubusercontent.com
```

Los roles IAM deben restringir:

- `aud` a `sts.amazonaws.com`.
- `sub` al repositorio, rama y entorno autorizados.
- Permisos de despliegue al mínimo necesario.

No se deben crear usuarios IAM para GitHub Actions ni almacenar access keys en secrets de GitHub.

Ver [`bootstrap/oidc-y-buckets.md`](../bootstrap/oidc-y-buckets.md).

## 6. Separación por alternativa

Cada alternativa de IaC debe tener:

- Su propio rol de CI/CD.
- Su propio estado.
- Su propio entorno de GitHub.
- Su propia aprobación.

No se debe usar un mismo rol para desplegar Terraform, Pulumi y CloudFormation sin una revisión de permisos.

## 7. Flujo de aplicación previsto

### Frontend

1. El repositorio frontend ejecuta pruebas y build con `VITE_API_URL=/api`.
2. El workflow asume un rol IAM mediante OIDC.
3. Usa SSM Run Command para invocar `/usr/local/bin/deploy-frontend.sh`.
4. El script ejecuta `git fetch`, `git reset`, `npm ci`, `VITE_API_URL=/api npm run build`, publica `dist`, recarga Nginx y comprueba `/healthz`.

### Backend

1. El repositorio backend ejecuta pruebas y build.
2. El workflow asume un rol IAM mediante OIDC.
3. Usa SSM Run Command para invocar `/usr/local/bin/deploy-backend.sh`.
4. El script ejecuta `git fetch`, `git reset`, `npm ci --omit=dev`, reinicia systemd y comprueba `/api/health`.
5. No reinicializa PostgreSQL ni ejecuta `schema.sql`.

## 8. Reglas de seguridad

- No imprimir variables de entorno con secretos.
- No usar `set -x` en pasos que manipulen secretos.
- No aprobar despliegues desde forks.
- No permitir `pull_request_target` para workflows con credenciales AWS.
- No reutilizar roles de infraestructura para aplicación.
- No habilitar auto-merge ni despliegues automáticos en esta etapa.

## 9. Configuración inicial requerida

1. Desplegar una de las alternativas IaC y esperar que SSM registre las instancias.
2. Obtener los ARN de `control-asistencia-github-frontend-deploy` y `control-asistencia-github-backend-deploy`.
3. Configurar en cada repositorio, dentro del environment protegido correspondiente:
   - `AWS_DEPLOY_ROLE_ARN`: ARN del rol específico.
   - `AWS_REGION`: `us-east-2` (opcional, el workflow tiene ese valor por defecto).
   - `SSM_INSTANCE_ID`: ID de la instancia frontend o backend.
4. Proteger los environments y restringir la rama `main`.
5. Confirmar que las instancias están `Online` en SSM.

Los roles OIDC restringen `aud` a `sts.amazonaws.com` y `sub` al repositorio y rama autorizados. Sus permisos SSM se limitan a `SendCommand` sobre instancias con la etiqueta `Name` del componente y a consultar el resultado del comando.

## 10. Prueba sin AWS

- Ejecutar `bash -n scripts/deploy-backend.sh scripts/deploy-frontend.sh`.
- Validar los YAML de ambos workflows y revisar que no contengan access keys.
- Ejecutar el generador de CloudFormation y las validaciones de Terraform/Pulumi.
- No es posible comprobar la ejecución SSM sin una instancia registrada; no se ejecutan workflows reales en esta etapa.

## 11. Estado de la Etapa 3E

- Workflows de aplicación implementados.
- Proveedor OIDC y roles IAM de GitHub Actions definidos en las tres alternativas IaC.
- Sin secretos AWS permanentes.
- Sin ejecuciones de workflows contra AWS.
