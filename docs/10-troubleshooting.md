# Troubleshooting

## 1. Cloud-Init no se ejecutó

Revisar:

```bash
sudo cloud-init status --long
sudo cat /var/log/cloud-init-output.log
sudo cat /var/log/control-asistencia/bootstrap.log
sudo cat /var/lib/control-asistencia/state/*/failed_step
```

Causas frecuentes:

- User-data mal renderizada o con placeholders sin sustituir.
- Falta de salida HTTPS (para SSM o S3).
- Instance profile sin permisos IAM para S3 o Secrets Manager.
- Checksum SHA-256 no coincide.
- Rol desconocido (distinto de `frontend` o `backend-db`).

## 2. Checksum incorrecto

Síntomas:

- El bootstrap se detiene.
- El log indica que el SHA-256 no coincide.

Acciones:

- Verificar que el bundle publicado sea el mismo que se versionó.
- Recalcular el checksum.
- Verificar que la IaC tenga el checksum correcto.
- No desactivar la verificación.

## 3. Session Manager no conecta

Revisar:

```bash
sudo systemctl status amazon-ssm-agent
sudo journalctl -u amazon-ssm-agent -n 100
```

Comprobar:

- Instance profile con `AmazonSSMManagedInstanceCore`.
- Salida HTTPS 443.
- DNS.
- Agente SSM instalado.
- Región correcta.
- La instancia aparece como “Managed Node” en SSM.

No abrir SSH como solución.

## 4. Nginx devuelve 502 en `/api/`

Causas:

- Backend detenido.
- IP privada incorrecta.
- Security Group del backend sin regla desde el frontend.
- Backend escuchando en una interfaz incorrecta.
- Puerto 3000 no disponible.

Verificar:

```bash
systemctl status control-asistencia-backend
curl -v http://<IP_PRIVADA_BACKEND>:3000/api/health
tail -n 100 /var/log/nginx/error.log
```

## 5. Nginx devuelve 404 en rutas de la SPA

La configuración debe incluir:

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

Verificar que el build se sirva desde la raíz y que los assets estén en `/assets/`.

## 6. El frontend llama a `localhost:3000`

El build no se realizó con `VITE_API_URL=/api`.

Acciones:

- Recompilar con `VITE_API_URL=/api`.
- Verificar el artefacto publicado.
- No editar el bundle compilado a mano si se puede evitar.

## 7. PostgreSQL no inicia

Revisar:

```bash
systemctl status postgresql
journalctl -u postgresql -n 100
```

Causas:

- Clúster no inicializado.
- Permisos incorrectos.
- Configuración inválida.
- Puerto ocupado.
- Espacio insuficiente en disco.

## 8. PostgreSQL acepta conexiones externas

Verificar:

```bash
grep -n "listen_addresses" /var/lib/pgsql/data/postgresql.conf
grep -n "^host" /var/lib/pgsql/data/pg_hba.conf
ss -lntp | grep 5432
```

Debe escuchar solo en `127.0.0.1` o `localhost`. No abrir `pg_hba.conf` a la red.

## 9. Error al aplicar `schema.sql`

El esquema contiene:

- `CREATE DATABASE control_asistencia;`
- `\connect control_asistencia;`

Estas instrucciones son específicas de `psql`. Un cliente SQL genérico puede fallar.

Acciones:

- Ejecutar con `psql` como usuario administrador local.
- O dividir el proceso en creación de base de datos y aplicación del esquema.
- No modificar el esquema sin revisar los datos demo existentes.
- Obtener la contraseña del administrador desde Secrets Manager.

## 10. Zona horaria incorrecta

Verificar:

```bash
timedatectl
psql -c "SHOW timezone;"
echo "$TZ"
date
```

Debe ser `America/La_Paz` en los tres niveles. Un desajuste puede afectar `CURRENT_DATE` y `LOCALTIME`.

## 11. Paquetes no encontrados en AL2023

Si `nodejs24`, `postgresql17-server` o `postgresql17-contrib` no aparecen:

- Verificar la versión de AL2023.
- Actualizar metadatos con `dnf makecache`.
- Revisar las notas de versión de AL2023.
- No usar repositorios de terceros sin una revisión de seguridad.

La disponibilidad fue verificada documentalmente para AL2023, pero debe confirmarse en la AMI exacta.

## 12. La IP pública cambió

Es esperado porque no se usa Elastic IP.

Acciones:

- Actualizar el acceso del usuario.
- Verificar que la configuración interna use IP privada.
- Considerar dominio/DNS y EIP para producción.

## 13. El backend no tiene salida a Internet

Aunque tenga IP pública, verificar:

- Route table con `0.0.0.0/0` al Internet Gateway.
- `MapPublicIpOnLaunch` o IP pública asignada.
- Security Group de salida.
- DNS.

Sin NAT, la salida depende de la IP pública y la ruta a IGW.

## 14. Se ejecutó un plan con cambios inesperados

Detenerse. No aplicar.

Revisar:

- Alternativa IaC correcta.
- Estado correcto.
- Región y cuenta.
- Variables.
- Recursos existentes.
- Si el plan intenta reemplazar la instancia backend, verificar respaldos.

## 15. Se detectó un secreto en el repositorio

1. No publicar el valor.
2. Revocar o rotar el secreto.
3. Revisar el historial Git.
4. Revisar logs y accesos AWS.
5. Documentar el incidente.
6. Actualizar controles para evitarlo.
