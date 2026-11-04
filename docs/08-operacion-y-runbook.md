# Operación y runbook

## 1. Alcance

Procedimientos operativos y runbooks para la arquitectura de Control de Asistencia basada en Amazon Linux 2023.
Implementación Cloud-Init correspondiente a la Etapa 3A.

## 2. Inspección de Inicialización (Cloud-Init)

Tras el primer arranque, verificar el estado y los logs de aprovisionamiento:

```bash
# Estado general de Cloud-Init
cloud-init status --long

# Bitácora de inicialización de la aplicación (modo 0640)
sudo tail -n 100 /var/log/control-asistencia/bootstrap.log

# Verificar marcador de finalización exitosa
cat /var/lib/control-asistencia/state/<frontend|backend-db>/complete
```

Si ocurrió algún fallo durante el bootstrap:
```bash
cat /var/lib/control-asistencia/state/<frontend|backend-db>/failed_step
```

## 2. Acceso administrativo

### Session Manager

1. Verificar que la instancia tenga el agente SSM en ejecución.
2. Verificar que el instance profile incluya `AmazonSSMManagedInstanceCore`.
3. Verificar salida HTTPS 443.
4. Abrir Session Manager desde la consola o AWS CLI.
5. No usar SSH.

Si Session Manager no conecta, revisar [`10-troubleshooting.md`](10-troubleshooting.md).

### Prohibiciones

- No abrir el puerto 22 para “probar”.
- No crear key pairs nuevos.
- No usar la IP pública del backend como método de administración.
- No compartir credenciales de AWS.

## 3. Servicios

### Frontend

| Elemento | Valor previsto |
| --- | --- |
| Servidor web | Nginx |
| Directorio | `/var/www/control-asistencia/current` |
| Configuración | `/etc/nginx/conf.d/control-asistencia.conf` |
| Proxy API | IP privada del backend en TCP 3000 |
| Logs | `/var/log/nginx/` |

Operaciones:

- Validar configuración: `nginx -t`.
- Recargar: `systemctl reload nginx`.
- Ver estado: `systemctl status nginx`.
- Ver logs: `journalctl -u nginx` y `/var/log/nginx/error.log`.

### Backend

| Elemento | Valor previsto |
| --- | --- |
| Runtime | Node.js 24 |
| Servicio | `control-asistencia-backend.service` |
| Directorio | `/opt/control-asistencia/backend/current` |
| Puerto | 3000 |
| Logs | `journalctl -u control-asistencia-backend` |
| Salud | `GET /api/health` |

Operaciones:

- Ver estado: `systemctl status control-asistencia-backend`.
- Reiniciar: `systemctl restart control-asistencia-backend`.
- Ver logs: `journalctl -u control-asistencia-backend -n 200`.
- Verificar salud desde la instancia: `curl -fsS http://127.0.0.1:3000/api/health`.

### PostgreSQL

| Elemento | Valor previsto |
| --- | --- |
| Versión | PostgreSQL 17 |
| Escucha | `localhost:5432` |
| Servicio | `postgresql` |
| Configuración | `/var/lib/pgsql/data/postgresql.conf` |
| Logs | `/var/lib/pgsql/data/log/` |

Operaciones:

- Ver estado: `systemctl status postgresql`.
- Ver conexiones: `psql -c "\l"` como usuario administrador local.
- Ver zona horaria: `SHOW timezone;`.
- No abrir `pg_hba.conf` a la red.

## 4. Zona horaria

La zona horaria debe ser `America/La_Paz` en:

- Sistema operativo.
- PostgreSQL.
- Entorno del backend.

Verificación:

```bash
timedatectl
psql -c "SHOW timezone;"
```

La lógica de asistencia usa `CURRENT_DATE` y `LOCALTIME`. Un desajuste puede mover una marcación al día equivocado.

## 5. Respaldos del volumen raíz

No hay un volumen EBS independiente para PostgreSQL. La política de respaldo debe cubrir el volumen raíz de la instancia backend.

### Requisitos

- Programar snapshots del volumen raíz.
- Definir retención.
- Verificar que el snapshot incluya PostgreSQL detenido o consistente.
- Probar la restauración en una instancia temporal.
- Documentar el RPO y RTO.
- No asumir que el snapshot es válido sin una prueba de restauración.

### Procedimiento previsto de restauración

1. Identificar el snapshot válido.
2. Crear una instancia temporal desde el snapshot.
3. Verificar PostgreSQL y el esquema.
4. Verificar datos de demostración y datos reales.
5. Exportar o copiar los datos necesarios.
6. Reemplazar la instancia solo con autorización.
7. Verificar SSM, Cloud-Init y aplicación.
8. Destruir la instancia temporal después de validar.

No se ejecuta en la Etapa 2.

## 6. Despliegue de nuevas versiones

### Frontend

1. Construir con `VITE_API_URL=/api`.
2. Publicar artefacto en S3.
3. Descargar en la instancia frontend vía SSM.
4. Actualizar el directorio `current` de forma atómica.
5. Validar Nginx.
6. Recargar Nginx.
7. Ejecutar smoke test.

### Backend

1. Construir artefacto.
2. Publicar artefacto en S3.
3. Descargar en la instancia backend vía SSM.
4. Instalar dependencias de producción.
5. Actualizar el directorio `current` de forma atómica.
6. Reiniciar el servicio.
7. Verificar `/api/health`.
8. Revisar logs.

No se debe recrear la instancia para un cambio de aplicación.

## 7. Rotación de secretos

1. Actualizar el valor en Secrets Manager.
2. Verificar que la aplicación pueda leer el nuevo valor.
3. Reiniciar el servicio backend si la aplicación carga secretos al inicio.
4. Verificar salud y funcionamiento.
5. Revocar el valor anterior si aplica.

La rotación automática requiere una implementación específica y no forma parte de la Etapa 2.

## 8. Cambio de IP pública

La IP pública del frontend es dinámica. Si la instancia se detiene y se inicia, o se reemplaza, la IP puede cambiar.

Consecuencias:

- Los usuarios deben usar la nueva IP.
- Un dominio con DNS estable es la solución recomendada para producción.
- No usar la IP pública en configuraciones internas.

El backend también tiene IP pública dinámica. Nginx usa su IP privada, no la pública.

## 9. Cambio de AMI o reemplazo de instancia

Antes de reemplazar:

1. Crear snapshot del volumen raíz del backend.
2. Verificar que el bundle de Cloud-Init esté disponible.
3. Verificar los secretos.
4. Verificar la versión de la aplicación.
5. Programar una ventana de mantenimiento.
6. Actualizar el artefacto o la configuración necesaria.
7. Reemplazar con aprobación.
8. Verificar SSM, Cloud-Init y aplicación.

## 10. Registro de cambios

Cada cambio debe registrar:

- Fecha y responsable.
- Alternativa IaC utilizada.
- Versión de Cloud-Init.
- Versión de frontend y backend.
- Cambios de infraestructura.
- Validaciones ejecutadas.
- Incidentes y rollback.

## 11. Rollback

- Frontend: restaurar el artefacto anterior en `current` y recargar Nginx.
- Backend: restaurar el artefacto anterior y reiniciar el servicio.
- Base de datos: restaurar desde snapshot solo con un procedimiento aprobado.
- Infraestructura: usar el estado y el plan de la alternativa correspondiente; no mezclar herramientas.

## 12. Estado de la Etapa 2

Este runbook es documentación prevista. No se han ejecutado respaldos, restauraciones, rotaciones ni despliegues.
