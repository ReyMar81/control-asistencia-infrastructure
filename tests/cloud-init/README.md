# Pruebas de Cloud-Init

Pruebas previstas para la Etapa 3. En la Etapa 2 solo se ejecutan verificaciones estáticas.

## Pruebas planificadas

- `bash -n` sobre todos los scripts y plantillas shell.
- `shellcheck` sobre scripts.
- Renderizado de user-data sin placeholders pendientes.
- Validación de checksum SHA-256.
- Validación de rol permitido.
- Idempotencia de instalación y configuración.
- Fallo controlado ante checksum incorrecto.
- Fallo controlado sin permisos S3.
- Verificación de que no se escriben secretos en logs.
- Verificación de zona horaria `America/La_Paz`.

## Estado

No se han ejecutado pruebas funcionales sobre una instancia. Los scripts de rol son esqueletos no funcionales.
