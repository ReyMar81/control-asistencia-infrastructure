# Smoke tests

Pruebas de solo lectura previstas después de un despliegue autorizado.

## Comprobaciones

- `GET /healthz` en Nginx devuelve 200.
- `GET /api/health` devuelve 200.
- La SPA carga desde `/`.
- Una ruta interna de la SPA devuelve `index.html`.
- `/api/` no se sirve como archivo estático.
- El frontend usa `/api` y no `localhost:3000`.

## Ejecución

```bash
./scripts/smoke-test.sh http://<IP-O-DOMINIO>
```

No se ejecutó contra AWS en la Etapa 2.
