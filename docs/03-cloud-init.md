# Cloud-Init — Implementación y Contratos de Inicialización

## 1. Alcance y Estado

Este documento define la arquitectura y el contrato unificado de inicialización mediante Cloud-Init para las instancias EC2 del proyecto Control de Asistencia:
- `frontend`: Nginx, compilación y publicación de la SPA React/Vite, reverse proxy `/api/`.
- `backend-db`: Node.js 24 LTS, PostgreSQL 17 local con SCRAM-SHA-256, inicialización segura de base de datos, servicio systemd y verificación de salud en `/api/health`.

**Estado actual:** Etapa 3A — Implementación funcional y validación local completada. Los scripts están preparados para Amazon Linux 2023 x86_64 y superan todas las pruebas locales con mocks. La publicación a S3 y el despliegue con IaC corresponden a la Etapa 3B.

## 2. Decisiones Arquitectónicas Obligatorias

| Parámetro | Valor | Justificación / Restricción |
| --- | --- | --- |
| Región AWS | `us-east-2` | Región estándar del proyecto |
| Sistema Operativo | Amazon Linux 2023 (AL2023) x86_64 | Plataforma oficial soportada por AWS |
| Node.js | 24 LTS | Paquete oficial `nodejs24` en AL2023 |
| PostgreSQL | 17 | Paquetes `postgresql17`, `postgresql17-server`, `postgresql17-contrib` |
| Servidor Web | Nginx | Sirve la SPA estática y hace proxy de API |
| Zona horaria | `America/La_Paz` | Zona horaria académica del diplomado |
| Puerto Backend | 3000 | Definido por `src/server.js` |
| PostgreSQL Host/Port | `127.0.0.1:5432` | Escucha exclusivamente en localhost con SCRAM |
| Proxy API en Nginx | `/api/` -> `http://<IP_PRIVADA>:3000` | Conserva el prefijo `/api` requerido por Express |
| Redirección `/api` | Redirección 308 a `/api/` | Evita errores 404 o caídas en la SPA |
| Build Frontend | `VITE_API_URL=/api npm run build` | Hace relativo el consumo del backend a través de Nginx |
| Gestión de Servicio | systemd | Servicio `control-asistencia-backend.service` bajo usuario `controlasistencia` |
| Administración EC2 | AWS Systems Manager (Session Manager) | **Sin puerto SSH (22) abierto** |
| Metadatos EC2 | IMDSv2 obligatorio | `HttpTokens: required`, `HttpPutResponseHopLimit: 1` |
| Secretos | AWS Secrets Manager | Recuperación con IAM Role en tiempo de ejecución |

## 3. Estructura del Repositorio de Cloud-Init

```text
cloud-init/
├── bootstrap.sh
├── common/
│   ├── lib.sh
│   ├── packages.sh
│   ├── postgres.sh
│   ├── secrets.sh
│   ├── validate.sh
│   └── parse-secret.mjs
├── roles/
│   ├── frontend.sh
│   └── backend-db.sh
├── files/
│   ├── nginx.conf
│   ├── nginx-control-asistencia.conf.tmpl
│   └── control-asistencia-backend.service.tmpl
└── user-data/
    ├── frontend.sh.tmpl
    └── backend-db.sh.tmpl
```

## 4. Flujo de Inicialización (First Boot)

1. **User-Data mínima**: IaC (Terraform, Pulumi o CloudFormation) inyecta la plantilla renderizada (`frontend.sh.tmpl` o `backend-db.sh.tmpl`).
2. **Validación de entorno**: La user-data verifica la ausencia de placeholders, valida el formato del checksum SHA-256 (64 hex) y comprueba la disponibilidad de AWS CLI v2.
3. **Descarga autenticada del bundle**: Mediante `aws s3 cp --region ...` con el IAM Role de la instancia.
4. **Comprobación de integridad**: Compara el hash SHA-256 del archivo descargado con el valor esperado. Si discrepa, aborta inmediatamente con código de error.
5. **Inspección de seguridad del archivo tar**: Verifica que el tar no contenga rutas absolutas, secuencias `..` o enlaces simbólicos maliciosos.
6. **Extracción y ejecución de bootstrap**: Descomprime en `/opt/control-asistencia/cloud-init/<version>` y ejecuta `./bootstrap.sh --role <rol>`.
7. **Ejecución del rol correspondiente**:
   - Carga librerías comunes y activa logging en `/var/log/control-asistencia/bootstrap.log`.
   - Valida el sistema operativo (`/etc/os-release` AL2023).
   - Configura la zona horaria `America/La_Paz` con `timedatectl`.
   - Crea el usuario y grupo de sistema `controlasistencia`.
   - Instala paquetes base y del rol correspondiente mediante `dnf`.
   - Ejecuta la lógica específica (`ca_frontend_main` o `ca_backend_main`).
8. **Finalización y estado**: Escribe el archivo `/var/lib/control-asistencia/state/<rol>/complete`.

## 5. Contrato de Variables y Parámetros

| Variable | Rol | Propósito | Formato / Validación |
| --- | --- | --- | --- |
| `CA_AWS_REGION` | Ambos | Región AWS | Expresión regular `^[a-z]{2}-[a-z]+-[0-9]$` |
| `CA_TIMEZONE` | Ambos | Zona horaria del sistema | `America/La_Paz` |
| `CA_BUNDLE_BUCKET` | Ambos | Bucket S3 del bundle Cloud-Init | Nombre DNS S3 válido |
| `CA_BUNDLE_KEY` | Ambos | Clave del bundle en S3 | Ruta relativa, sin `..` ni espacios |
| `CA_BUNDLE_VERSION` | Ambos | Identificador de versión | `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$` |
| `CA_BUNDLE_SHA256` | Ambos | Checksum SHA-256 del bundle | Hexadecimal 64 caracteres |
| `CA_ARTIFACT_BUCKET` | Ambos | Bucket S3 de los artefactos de código | Nombre DNS S3 válido |
| `CA_FRONTEND_ARTIFACT_KEY` | Frontend | Clave S3 del tar.gz del frontend | Ruta S3 válida |
| `CA_FRONTEND_ARTIFACT_SHA256` | Frontend | Hash SHA-256 del frontend | Hexadecimal 64 caracteres |
| `CA_BACKEND_PRIVATE_IP` | Frontend | IP privada del backend para Nginx | RFC 1918 (no link-local) |
| `CA_BACKEND_ARTIFACT_KEY` | Backend | Clave S3 del tar.gz del backend | Ruta S3 válida |
| `CA_BACKEND_ARTIFACT_SHA256` | Backend | Hash SHA-256 del backend | Hexadecimal 64 caracteres |
| `CA_SECRET_ID` | Backend | Nombre o ARN del secreto en Secrets Manager | String no vacío sin saltos |
| `CA_CLIENT_URL` | Backend | URL permitida por CORS en backend | URL HTTP/HTTPS válida |
| `CA_RESET_ADMIN_PASSWORD` | Backend | Flag para forzar actualización de pass admin | `0` o `1` |

## 6. Contrato de Secretos (Secrets Manager)

El backend recupera un único secreto JSON identificado por `CA_SECRET_ID`:
```json
{
  "DATABASE_URL": "postgres://ca_app:<password>@localhost:5432/control_asistencia",
  "JWT_SECRET": "<clave-secreta-min-32-chars>",
  "ADMIN_PASSWORD": "<clave-admin-min-12-chars>"
}
```
El script `common/parse-secret.mjs` valida sintácticamente el JSON, confirma que el host sea estrictamente local (`localhost`, `127.0.0.1` o `::1`) en el puerto 5432, verifica longitudes mínimas y extrae usuario, contraseña y nombre de base de datos de manera segura delimitada por caracteres nulos (`\0`).

El archivo de configuración de entorno generado `/etc/control-asistencia/backend.env` contiene:
```bash
NODE_ENV="production"
PORT="3000"
DATABASE_URL="postgres://..."
JWT_SECRET="..."
CLIENT_URL="http://..."
```
Permisos del archivo: `0600`, propietario `controlasistencia:controlasistencia`.

## 7. Tratamiento de PostgreSQL y `schema.sql`

El archivo `schema.sql` provisto en el repositorio backend contiene comandos orientados a inicialización interactiva (`CREATE DATABASE`, `\connect`, extensiones y seeds demo).
Para ejecutarlo de forma limpia, desatendida e idempotente:
1. `ca_filter_schema` procesa el archivo con `awk` eliminando las cláusulas `CREATE DATABASE` y `\connect`.
2. `ca_create_database` crea la base de datos `control_asistencia` UTF8 asignada al rol de aplicación `ca_app`.
3. `ca_create_extensions` ejecuta `CREATE EXTENSION IF NOT EXISTS` para `citext`, `pgcrypto` y `unaccent` con el rol de superusuario de Postgres.
4. `ca_validate_schema_safety` inspecciona el archivo resultante para garantizar que no contenga sentencias no autorizadas (`DROP DATABASE`, `TRUNCATE`, `DELETE FROM`, etc.).
5. Se calcula el SHA-256 del esquema filtrado y se almacena en `/var/lib/control-asistencia/state/backend-db/schema-<hash>`. Si coincide, se omite su reejecución.
6. `ca_update_admin_password` actualiza la contraseña de `admin@asistencia.local` con `crypt('<password>', gen_salt('bf'))` usando la contraseña provista por Secrets Manager, evitando que la contraseña demo por defecto permanezca activa.

## 8. Idempotencia y Recuperación

- Directorio de estado: `/var/lib/control-asistencia/state/<rol>/`.
- Marcadores de paso:
  - `package-base`: instalación de herramientas base y SSM.
  - `package-<rol>`: instalación de paquetes de rol (Nginx, Node.js 24, PostgreSQL 17).
  - `<rol>-release-<version>-<hash>`: descarga, extracción y compilación del artefacto.
  - `nginx-<hash>`: configuración del virtual host y validación con `nginx -t`.
  - `schema-<hash>`: esquema SQL aplicado.
  - `admin-password`: actualización de credenciales del administrador inicial.
- Si un paso falla, se activa el trap de error en `common/lib.sh`, se registra el motivo en `/var/log/control-asistencia/bootstrap.log` y se escribe el archivo `failed_step`.
- Para reprocesar:
  ```bash
  sudo rm -f /var/lib/control-asistencia/state/<rol>/failed_step
  sudo /opt/control-asistencia/cloud-init/<version>/bootstrap.sh --role <rol>
  ```

## 9. Pruebas Locales y Limitaciones

Las pruebas locales implementadas en `tests/cloud-init/` validan:
- Sintaxis bash (`bash -n`).
- Sustitución completa de variables de user-data sin placeholders residuales.
- Utilidades de hashing, extracción y parsing de secretos.
- Flujo completo de ejecución mediante mocks locales (`tests/mocks/`) de `aws`, `systemctl`, `dnf`, `psql`, `rpm` y `npm`.
- Escaneo de secretos sensibles en el repositorio.

**Limitaciones de la validación local:**
- No ejecuta el binario real de PostgreSQL ni compila módulos nativos de Linux en Windows.
- La comunicación real con los servicios de AWS (Secrets Manager, S3, SSM) y la red EC2 se validará en la Etapa 3B.

## 10. Pendientes para Etapa 3B

1. Empaquetar el bundle funcional definitivo y cargarlo en el bucket S3 de artefactos.
2. Registrar la versión del bundle y su checksum SHA-256 en la configuración de IaC (Terraform, Pulumi, CloudFormation).
3. Desplegar los recursos en AWS (`us-east-2`).
4. Conectar mediante AWS Systems Manager Session Manager para verificar la inicialización real y el estado del servicio en EC2.
