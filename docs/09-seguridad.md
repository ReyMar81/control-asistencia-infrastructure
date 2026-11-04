# Seguridad

## 1. Modelo de seguridad

La arquitectura aplica defensa en profundidad con estos controles:

- Segmentación mediante Security Groups.
- Ausencia de SSH público.
- Administración exclusiva por Systems Manager.
- PostgreSQL limitado a localhost.
- Secretos en Secrets Manager.
- Roles IAM de mínimo privilegio.
- IMDSv2 obligatorio.
- CI/CD con OIDC.
- Cloud-Init verificado por checksum.

La Etapa 3A implementa funcionalmente y valida de manera estricta estos controles a nivel de scripts de inicialización:
- Permisos `0600` en `/etc/control-asistencia/backend.env` asignado a `controlasistencia:controlasistencia`.
- PostgreSQL 17 configurado con `scram-sha-256`, escuchando solo en `localhost`, sin reglas `trust`.
- Sanitización absoluta de logs: contraseñas, URLs completas y JWT_SECRET nunca se escriben en `/var/log/control-asistencia/bootstrap.log`.
- Verificación criptográfica SHA-256 previa a la descompresión del bundle y de artefactos de aplicación.
- Sandboxing en systemd (`ProtectSystem=strict`, `NoNewPrivileges=true`, `PrivateTmp=true`, `ProtectHome=true`).
- Sin SSH habilitado; acceso exclusivo mediante AWS Systems Manager.
- IMDSv2 requerido.

## 2. Superficie de ataque

| Componente | Exposición | Control |
| --- | --- | --- |
| Frontend | TCP 80/443 desde Internet | SG frontend, Nginx |
| Backend | TCP 3000 solo desde SG frontend | SG backend |
| PostgreSQL | `localhost:5432` | Sin regla de red |
| SSH | Ninguna | SSM |
| SSM | Salida 443 | Instance profile |
| S3 bundle | Lectura desde instancias | IAM por prefijo |
| Secrets Manager | Lectura desde backend | IAM por secreto |
| GitHub Actions | OIDC | Rol por repositorio y entorno |

## 3. Mínimo privilegio

### Instancia frontend

Permisos previstos:

- `AmazonSSMManagedInstanceCore`.
- Lectura del prefijo S3 del bundle de Cloud-Init.
- Lectura del parámetro SSM con la IP privada del backend.
- Escritura de logs en CloudWatch.
- Lectura de artefactos de frontend en S3.

No debe tener:

- Acceso a secretos de base de datos.
- Permisos de administrador.
- Permisos para modificar IAM.
- Permisos para crear recursos.

### Instancia backend-db

Permisos previstos:

- `AmazonSSMManagedInstanceCore`.
- Lectura del prefijo S3 del bundle de Cloud-Init.
- Lectura de los secretos de aplicación.
- Lectura de parámetros SSM del proyecto.
- Escritura de logs en CloudWatch.
- Lectura de artefactos de backend en S3.

No debe tener:

- Permisos de administrador.
- Permisos para modificar IAM.
- Acceso a secretos de otros proyectos.
- Permisos para crear recursos.
- Permisos para modificar el bucket de estado.

### GitHub Actions

Cada rol debe limitarse por:

- Repositorio.
- Rama.
- Entorno.
- Servicio.
- Acciones permitidas.

No se deben usar access keys estáticas.

## 4. Security Groups

### Frontend

Entrada:

- TCP 80 desde `0.0.0.0/0`.
- TCP 443 desde `0.0.0.0/0` para el futuro TLS.

Salida:

- TCP 3000 al Security Group del backend.
- TCP 443 a Internet para SSM, S3, Secrets Manager, actualizaciones y GitHub.
- DNS.

### Backend

Entrada:

- TCP 3000 desde el Security Group del frontend.
- Sin SSH.
- Sin PostgreSQL desde la red.

Salida:

- TCP 443 a Internet para SSM, S3, Secrets Manager, actualizaciones y GitHub.
- DNS.

### PostgreSQL

No se crea un Security Group dedicado para PostgreSQL porque el servicio escucha solo en localhost. La protección combina la configuración del servicio y el hecho de que el Security Group del backend no abre TCP 5432.

## 5. IMDSv2

Todas las instancias deben configurar:

```text
HttpTokens: required
HttpPutResponseHopLimit: 1
HttpEndpoint: enabled
```

Esto reduce el riesgo de que una vulnerabilidad SSRF lea credenciales del instance profile.

## 6. Secretos

- `DATABASE_URL` debe construirse con la contraseña obtenida de Secrets Manager.
- `JWT_SECRET` debe ser aleatorio y no reutilizado entre entornos.
- `ADMIN_PASSWORD` debe obtenerse de Secrets Manager.
- No se deben imprimir secretos en logs.
- Los archivos temporales con secretos deben tener permisos `0600`.
- Los secretos no deben incluirse en el bundle S3.
- El frontend no debe recibir secretos de backend.

## 7. Riesgos de la alternativa económica

| Riesgo | Impacto | Mitigación |
| --- | --- | --- |
| Backend con IP pública | Mayor superficie de red | SG restrictivo y sin puertos de administración |
| Sin NAT Gateway | Salida directa a Internet | Security Groups y monitoreo |
| PostgreSQL en la misma instancia | Fallo único | Backups y restauración probada |
| Volumen raíz compartido | Pérdida de datos si se reemplaza | Snapshots programados |
| IP pública dinámica | Cambio de acceso | Dominio/EIP en producción |
| Sin ALB | Sin alta disponibilidad | Aceptado para entorno económico |
| Sin TLS inicial | Tráfico HTTP sin cifrar | HTTPS antes de producción |
| Sin WAF | Menos protección perimetral | Evaluar en producción |

## 8. Riesgos heredados

Las credenciales expuestas en proyectos anteriores deben revocarse o rotarse. También se debe revisar el historial Git y CloudTrail. Estas acciones no se han ejecutado y requieren autorización.

No se deben reutilizar:

- Access keys.
- Usuarios IAM con AdministratorAccess.
- Security Groups antiguos.
- Key pairs antiguos.
- Instancias de prueba.
- Estados remotos.

## 9. Verificaciones de seguridad previstas

Antes de un despliegue:

- Confirmar que no hay secretos en el repositorio.
- Confirmar que `.gitignore` excluye estados y archivos locales.
- Revisar `terraform plan`, `pulumi preview` o change set.
- Confirmar que no hay reglas SSH.
- Confirmar que el backend solo acepta 3000 desde el frontend.
- Confirmar IMDSv2.
- Confirmar que PostgreSQL escucha en localhost.
- Confirmar que el frontend compila con `VITE_API_URL=/api`.
- Confirmar que los secretos existen en Secrets Manager.
- Confirmar que el bundle coincide con el checksum.
- Confirmar que los workflows no se ejecutan automáticamente.

## 10. Limitaciones documentadas

- La arquitectura no es de alta disponibilidad.
- La base de datos no está separada de la aplicación.
- La administración depende de SSM.
- La IP pública del frontend puede cambiar.
- La alternativa no reemplaza una revisión de seguridad formal.
- La Etapa 2 no ha validado controles en AWS.
