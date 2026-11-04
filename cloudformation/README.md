# CloudFormation

## Estado

**Etapa 3D — implementación lista para validación local.**

`template.yaml` define la arquitectura completa. El archivo se genera con `scripts/render-cloudformation.py`, que incorpora las plantillas Cloud-Init compartidas sin duplicarlas en el código fuente.

## Archivos

| Archivo | Propósito |
| --- | --- |
| `template.yaml` | Plantilla generada y desplegable |
| `template.yaml.tmpl` | Fuente CloudFormation con marcadores para Cloud-Init |
| `parameters.dev.json.example` | Ejemplo de parámetros sin secretos |

## Convenciones

- Región `us-east-2`.
- VPC `10.10.0.0/16`.
- Una subnet pública `10.10.1.0/24`.
- Sin NAT Gateway.
- Sin SSH.
- IMDSv2 obligatorio.
- Backend con IP pública dinámica y puerto 3000 restringido al SG frontend.
- PostgreSQL en localhost.
- Parámetros `NoEcho` para contraseña de base de datos y JWT secret.
- Cloud-Init desde las plantillas locales compartidas.

## Flujo previsto

1. Ejecutar `python scripts/render-cloudformation.py` después de modificar Cloud-Init.
2. Validar la plantilla localmente.
3. Crear un change set en un entorno autorizado.
4. Revisar el change set.
5. Desplegar solo con aprobación explícita.

La Etapa 2 no ejecuta validaciones contra AWS ni crea stacks.

Ver [`../docs/06-cloudformation.md`](../docs/06-cloudformation.md).
