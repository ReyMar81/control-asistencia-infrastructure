# Pruebas de seguridad

Comprobaciones previstas antes y después de un despliegue autorizado.

## Infraestructura

- El SG del frontend no tiene TCP 22.
- El SG del backend no tiene TCP 22.
- El SG del backend solo acepta TCP 3000 desde el SG del frontend.
- PostgreSQL no tiene reglas de entrada de red.
- Las instancias tienen IMDSv2 requerido.
- Las instancias tienen instance profile.
- Los roles IAM no tienen `AdministratorAccess`.
- Los buckets bloquean acceso público.
- Los secretos no están en el repositorio.

## Aplicación

- PostgreSQL escucha en localhost.
- El backend no responde en la IP pública desde Internet.
- El frontend compila con `VITE_API_URL=/api`.
- No hay secretos en logs.
- No hay secretos en variables expuestas al frontend.

## Repositorio

Ejecutar:

```bash
./tests/security/check-repository-secrets.sh
```

La comprobación es estática y no accede a AWS.
