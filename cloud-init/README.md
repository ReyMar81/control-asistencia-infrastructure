# Cloud-Init — Control de Asistencia

Fuente única de scripts, plantillas y contratos de inicialización para las instancias `frontend` y `backend-db`.

## 1. Estado

**Etapa 3A-R — Simplificación funcional Cloud-Init YAML para Demostración Académica.**
Se implementaron dos plantillas Cloud-Init nativas en formato YAML (`#cloud-config`) diseñadas para ser consumidas indistintamente por **Terraform**, **Pulumi** y **CloudFormation**:
- `cloud-init/user-data/frontend.yaml.tmpl`
- `cloud-init/user-data/backend.yaml.tmpl`

Ambas plantillas estructuran explícitamente los tres bloques canónicos de Cloud-Init:
1. `packages`: dependencias del sistema operativo (Git, Node.js 24, Nginx, PostgreSQL 17).
2. `write_files`: configuraciones, archivos de entorno (`backend.env`), unidades systemd, inicializador de base de datos y scripts de actualización continua para GitHub Actions vía SSM (`deploy-frontend.sh`, `deploy-backend.sh`).
3. `runcmd`: orquestación de clonado del repositorio oficial, instalación de dependencias (`npm ci`), preparación de esquema y puesta en marcha.

Se mantienen también los scripts auxiliares y validaciones previas de la Etapa 3A.

## 2. Arquitectura de archivos

```text
cloud-init/
├── README.md                                 # Esta documentación técnica
├── bootstrap.sh                              # Punto de entrada unificado que valida y ejecuta el rol
├── common/
│   ├── lib.sh                                # Logging, utilidades de FS, idempotencia y manejo de errores (traps)
│   ├── packages.sh                           # Instalación y verificación de Node.js 24, Nginx, PostgreSQL 17 y SSM
│   ├── postgres.sh                           # Inicialización idempotente, pg_hba.conf, extensiones y schema.sql
│   ├── secrets.sh                            # Recuperación y parsing seguro desde Secrets Manager (sin filtrar secretos)
│   ├── validate.sh                           # Validaciones estrictas de variables, IPs privadas y formatos
│   └── parse-secret.mjs                      # Validador y parser JSON en Node.js para el contrato de secretos
├── roles/
│   ├── frontend.sh                           # Descarga artefacto frontend, npm ci, build con VITE_API_URL=/api, Nginx
│   └── backend-db.sh                         # Descarga artefacto backend, npm ci --omit=dev, DB setup, systemd
├── files/
│   ├── nginx.conf                            # Configuración global endurecida de Nginx
│   ├── nginx-control-asistencia.conf.tmpl     # Virtual host con SPA fallback y reverse proxy a /api/
│   └── control-asistencia-backend.service.tmpl # Unidad systemd endurecida para el backend
└── user-data/
    ├── frontend.sh.tmpl                      # User-data EC2: descarga y valida bundle, invoca bootstrap rol frontend
    └── backend-db.sh.tmpl                    # User-data EC2: descarga y valida bundle, invoca bootstrap rol backend-db
```

## 3. Contrato de variables de entrada

### Variables comunes (ambos roles)
- `CA_AWS_REGION`: Región AWS (`us-east-2`).
- `CA_TIMEZONE`: Zona horaria obligatoria (`America/La_Paz`).
- `CA_BUNDLE_BUCKET`: Nombre del bucket S3 del bundle de Cloud-Init.
- `CA_BUNDLE_KEY`: Clave S3 del bundle comprimido.
- `CA_BUNDLE_VERSION`: Identificador explícito de versión (p. ej. `v0.1.0`).
- `CA_BUNDLE_SHA256`: Hash SHA-256 (64 caracteres hexadecimales) para verificar integridad antes de extraer.
- `CA_ARTIFACT_BUCKET`: Bucket S3 donde residen los artefactos de aplicación.
- `CA_APP_USER` / `CA_APP_GROUP`: Usuario de sistema sin privilegios (`controlasistencia`).

### Variables específicas del Frontend
- `CA_FRONTEND_ARTIFACT_KEY`: Clave S3 del artefacto frontend (`tar.gz`).
- `CA_FRONTEND_ARTIFACT_SHA256`: Hash SHA-256 del artefacto frontend.
- `CA_BACKEND_PRIVATE_IP`: IP privada de la instancia backend (validada en rangos RFC 1918, sin link-local).

### Variables específicas del Backend
- `CA_BACKEND_ARTIFACT_KEY`: Clave S3 del artefacto backend (`tar.gz`).
- `CA_BACKEND_ARTIFACT_SHA256`: Hash SHA-256 del artefacto backend.
- `CA_SECRET_ID`: Nombre o ARN del secreto en AWS Secrets Manager.
- `CA_CLIENT_URL`: URL base del cliente frontend permitida por CORS (p. ej. `http://<ip-o-dominio>`).
- `CA_RESET_ADMIN_PASSWORD`: Bandera (`0` o `1`) para forzar resincronización de la contraseña del administrador.

## 4. Contrato de secretos (AWS Secrets Manager)

El backend consume un único secreto en formato JSON con la siguiente estructura validada por `common/parse-secret.mjs`:
```json
{
  "DATABASE_URL": "postgres://ca_app:<password>@localhost:5432/control_asistencia",
  "JWT_SECRET": "<clave-secreta-min-32-caracteres>",
  "ADMIN_PASSWORD": "<contraseña-min-12-caracteres>"
}
```
Reglas de validación:
- `DATABASE_URL` debe apuntar estrictamente a `localhost` o `127.0.0.1` en el puerto `5432`.
- `JWT_SECRET` debe tener longitud mínima de 32 caracteres y sin caracteres de control.
- `ADMIN_PASSWORD` debe tener longitud mínima de 12 caracteres.
- Las variables nunca se imprimen en logs ni en consola; el archivo resultante `/etc/control-asistencia/backend.env` se crea con permisos `0600` perteneciente al usuario `controlasistencia:controlasistencia`.

## 5. Estrategia de base de datos (PostgreSQL 17)

El script `common/postgres.sh` maneja las particularidades de `backend-control-asistencia/schema.sql`:
1. **Inicialización del clúster**: Ejecuta `postgresql-setup --initdb` solo si no existe `PGDATA/PG_VERSION`.
2. **Configuración de red y autenticación**:
   - `listen_addresses = 'localhost'` (sin exposición en interfaces externas).
   - Autenticación `scram-sha-256` en `pg_hba.conf` para sockets Unix y TCP locales (127.0.0.1/32 y ::1/128). Se rechaza cualquier regla `trust`.
3. **Rol y Base de Datos**: Crea el rol de aplicación sin permisos de superusuario y la base de datos `control_asistencia` UTF8 asignando propiedad al usuario de aplicación.
4. **Extensiones**: Instala `citext`, `pgcrypto` y `unaccent` directamente con el usuario administrativo de Postgres.
5. **Filtrado seguro de `schema.sql`**: Remueve dinámicamente sentencias `CREATE DATABASE` y `\connect` para ejecutarse de forma limpia en la base de datos ya conectada.
6. **Validación de seguridad de esquema**: Bloquea sentencias destructivas (`DROP DATABASE`, `TRUNCATE`, `DELETE FROM`, `COPY ... PROGRAM`).
7. **Idempotencia y Administrador**: Calcula el SHA-256 del esquema para no re-ejecutarlo si no ha cambiado; actualiza la contraseña del administrador demo (`admin@asistencia.local`) con `crypt()` usando el valor provisto en Secrets Manager.

## 6. Configuración de Nginx y Frontend

1. Instala dependencias con `npm ci` a partir del lockfile real.
2. Compila la SPA con `VITE_API_URL=/api npm run build`.
3. Publica la release atómicamente mediante un symlink `/var/www/control-asistencia/current`.
4. Nginx aplica `try_files $uri $uri/ /index.html` para el enrutamiento de la SPA.
5. Configura `location /api/` con `proxy_pass http://<BACKEND_PRIVATE_IP>:3000;` (sin trailing slash en proxy_pass) para preservar la ruta `/api/...` hacia Express.
6. Configura `location = /api` con redirección 308 permanente hacia `/api/` para conservar método y cuerpo HTTP.
7. Expone endpoint de salud local `/healthz`.

## 7. Servicio systemd del backend

El servicio `control-asistencia-backend.service` se instala en `/etc/systemd/system/`:
- Ejecutado por el usuario no privilegiado `controlasistencia`.
- `WorkingDirectory=/opt/control-asistencia/backend/current`.
- `EnvironmentFile=/etc/control-asistencia/backend.env` (permisos `0600`).
- Comando de arranque: `node src/server.js`.
- Dependencia de PostgreSQL: `After=network-online.target postgresql.service`.
- Política de reinicio: `Restart=on-failure`, `RestartSec=5s`.
- Sandboxing: `ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`, `NoNewPrivileges=true`.

## 8. Idempotencia y recuperación

- Estados y pasos completados se almacenan bajo `/var/lib/control-asistencia/state/<rol>/`.
- Cada operación (paquetes base, paquetes de rol, descarga de release, configuración Nginx, setup de BD, schema hash, password admin) genera un marcador con hash de contenido.
- Si una ejecución falla, el archivo `complete` no se crea y se registra el paso fallido en `failed_step`.
- Para reintentar tras corregir un error:
  ```bash
  sudo rm -f /var/lib/control-asistencia/state/<rol>/failed_step
  sudo /opt/control-asistencia/cloud-init/<version>/bootstrap.sh --role <rol>
  ```

## 9. Logs y Diagnóstico

- Log principal de bootstrap: `/var/log/control-asistencia/bootstrap.log` (modo `0640`).
- Manejo estricto de errores: `set -euo pipefail` con trap de errores que reporta línea, código de salida y paso actual.
- Los logs sanitizan cualquier secreto; ninguna contraseña, token JWT o cadena de conexión sensible es emitida a la bitácora.
- Servicio backend: `journalctl -u control-asistencia-backend -f`.

## 10. Validación local

Se dispone de una suite completa de pruebas locales:
- `tests/cloud-init/test-static.sh`: sintaxis de todos los scripts y validación de tokens.
- `tests/cloud-init/test-render.sh`: renderizado de user-data y comprobación de parámetros obligatorios.
- `tests/cloud-init/test-lib.sh`: utilidades comunes, verificación SHA-256, extracción segura de tar, filtrado de schema y parsing de secretos.
- `tests/cloud-init/test-integration.sh`: ejecución integral de ambos roles simulando entorno AL2023 con mocks de AWS CLI, systemctl, dnf, psql, npm y curl.
- `tests/security/check-repository-secrets.sh`: escaneo estricto contra secretos en el código.
- `scripts/publish-cloud-init.sh --package-only`: genera el bundle reproducible `cloud-init-bundle.tar.gz` y valida su checksum.
