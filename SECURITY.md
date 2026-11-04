# Política de seguridad

## Alcance

Este documento establece las reglas de seguridad para el repositorio de infraestructura de Control de Asistencia y para cualquier despliegue futuro en AWS.

La Etapa 2 es de preparación. No se han creado ni modificado recursos AWS y no se han implementado todavía los scripts funcionales de Cloud-Init.

## Reglas obligatorias

1. No almacenar contraseñas, tokens, JWT_SECRET, DATABASE_URL ni credenciales AWS en el repositorio.
2. No incluir secretos reales en `.tfvars`, YAML, JSON, scripts, pruebas, documentación ni ejemplos.
3. No reutilizar las access keys encontradas en los proyectos anteriores.
4. No copiar credenciales desde `tf_stackflow/terraform`, `tf_stackflow/tofu` ni ningún otro proyecto.
5. No crear access keys estáticas para GitHub Actions. La estrategia objetivo es OIDC con roles de corta duración.
6. No exponer SSH a Internet. La administración remota debe realizarse mediante AWS Systems Manager Session Manager.
7. No abrir PostgreSQL a la red. PostgreSQL debe escuchar únicamente en `localhost:5432`.
8. No permitir tráfico al puerto 3000 desde Internet. Solo el Security Group del frontend puede acceder al backend.
9. Exigir IMDSv2 en todas las instancias EC2.
10. Aplicar el principio de mínimo privilegio a roles IAM, Security Groups y políticas de secretos.
11. No modificar ni eliminar los recursos IAM, proyectos Terraform/OpenTofu, estados remotos, instancias, Security Groups o key pairs anteriores.
12. No desplegar Terraform, Pulumi y CloudFormation simultáneamente sobre el mismo entorno.

## Credenciales expuestas en proyectos anteriores

La auditoría encontró credenciales AWS en texto plano en proyectos Terraform y OpenTofu anteriores, además de un usuario IAM con `AdministratorAccess` y una access key activa.

Acciones requeridas antes de cualquier despliegue:

- Revocar o rotar las access keys expuestas.
- Revisar el historial Git de los repositorios afectados para determinar el alcance de la exposición.
- Revisar CloudTrail y eventos de AWS para detectar uso no autorizado.
- Sustituir el usuario con privilegios administrativos por roles de mínimo privilegio y OIDC.
- No realizar estas acciones desde este repositorio sin autorización expresa y un procedimiento aprobado.

Estas acciones no forman parte de la Etapa 2 y no se han ejecutado.

## Secretos de aplicación

Los secretos previstos son:

- `DATABASE_URL`
- `JWT_SECRET`
- `ADMIN_PASSWORD`
- Contraseña del usuario de base de datos, si se separa del administrador.

Deben almacenarse en AWS Secrets Manager y ser leídos por la instancia backend mediante su rol IAM. No deben escribirse en Cloud-Init, en el bundle S3, en los repositorios de aplicación ni en archivos de configuración versionados.

La contraseña del administrador inicial no debe quedar codificada en `schema.sql`, scripts, seeds ni documentación. El proceso de inicialización deberá obtenerla desde Secrets Manager.

## Security Groups

Diseño previsto:

| Grupo | Entrada | Salida |
| --- | --- | --- |
| Frontend | TCP 80 y 443 desde `0.0.0.0/0` | TCP 3000 al SG backend; TCP 443 a Internet; DNS |
| Backend-db | TCP 3000 únicamente desde el SG frontend | TCP 443 a Internet; DNS |
| PostgreSQL | Sin reglas de entrada desde la red | No aplica; solo `localhost` |

No se crearán reglas para TCP 22.

La IP pública del backend no cambia el diseño de acceso: el Security Group sigue siendo el control efectivo. Esta es una limitación económica documentada y debe revisarse si el proyecto requiere aislamiento de red más estricto.

## IAM

- Roles separados para frontend y backend-db.
- `AmazonSSMManagedInstanceCore` para administración remota.
- Permiso de lectura del bundle S3 limitado al prefijo y versión necesarios.
- Permiso de lectura de Secrets Manager limitado a los secretos de aplicación.
- Permiso de lectura o escritura de parámetros SSM limitado a los nombres del proyecto.
- Permiso de escritura de logs en CloudWatch limitado al grupo del proyecto.
- Sin permisos de administrador.
- Sin access keys de largo plazo en instancias.

## IMDSv2

Todas las instancias deben configurar:

- `HttpTokens: required`
- `HttpPutResponseHopLimit: 1` o el mínimo compatible con el arranque
- `HttpEndpoint: enabled`

El uso de IMDSv2 reduce el riesgo de acceso a credenciales del instance profile mediante SSRF.

## CI/CD

- GitHub Actions utilizará OIDC para asumir roles IAM.
- Los roles de CI/CD deben limitarse por repositorio, rama y entorno.
- Los workflows de aplicación no deben tener permisos de infraestructura.
- Los despliegues de infraestructura deben requerir aprobación manual.
- Los workflows de esta etapa son esqueletos y no ejecutan operaciones de despliegue.

Ver [`docs/07-ci-cd.md`](docs/07-ci-cd.md).

## Datos y respaldos

PostgreSQL utilizará el volumen raíz de la instancia, sin un volumen EBS independiente. Esto reduce costo y complejidad, pero implica que la recuperación depende de:

- Copias de seguridad programadas del volumen raíz.
- Pruebas periódicas de restauración.
- Un procedimiento documentado de reconstrucción.

La ausencia de un volumen dedicado no elimina la necesidad de una política de respaldo. Ver [`docs/08-operacion-y-runbook.md`](docs/08-operacion-y-runbook.md).

## Reporte de incidentes

Si se detecta un secreto expuesto:

1. No publicar el valor en issues, pull requests ni chats.
2. Revocar o rotar el secreto afectado.
3. Revisar el historial de Git y los registros de AWS.
4. Documentar el incidente y las acciones tomadas.
5. Actualizar este documento si cambia el procedimiento.

## Limitaciones conocidas de la alternativa económica

- El backend tiene IP pública para evitar NAT Gateway.
- No hay alta disponibilidad ni balanceador de carga.
- PostgreSQL comparte la instancia con el backend.
- El frontend tiene IP pública dinámica; si se reemplaza la instancia, la IP cambia.
- No hay dominio ni TLS configurados en esta etapa.
- La administración depende de SSM y de conectividad saliente.
- Los respaldos deben implementarse explícitamente; no son automáticos por usar EC2.

Estas limitaciones deben revisarse antes de un entorno de producción.
