# Auditoría técnica y de seguridad

## 1. Alcance

La auditoría revisó el workspace local, los repositorios de aplicación y los proyectos de infraestructura existentes, además de realizar consultas de solo lectura a AWS.

No se modificaron archivos, estados remotos, recursos AWS ni repositorios de aplicación durante la auditoría.

## 2. Aplicación real

### Backend

- Node.js, Express y PostgreSQL.
- Módulos ES (`type: module`).
- Express 4.x, `pg`, `jsonwebtoken`, `bcryptjs`, `multer`, `xlsx`, `cors` y `dotenv`.
- Escucha en el puerto 3000.
- Expone `GET /api/health`.
- Usa `DATABASE_URL` para conectarse a PostgreSQL.
- Usa `CLIENT_URL` para CORS.
- El login de estudiante no exige contraseña; es un riesgo funcional que debe revisarse en el repositorio backend.
- La lógica de asistencia utiliza `CURRENT_DATE` y `LOCALTIME` de PostgreSQL.

### Frontend

- React 18 y Vite 5.
- La URL de API se toma de `import.meta.env.VITE_API_URL` con valor por defecto `http://localhost:3000/api`.
- `VITE_API_URL` se incorpora en tiempo de build. Para producción debe compilarse con `VITE_API_URL=/api`.
- El build existente utiliza rutas absolutas `/assets/...`; Nginx debe servir la SPA desde la raíz del sitio.

### Base de datos

- El esquema requiere PostgreSQL con extensiones `citext`, `pgcrypto` y `unaccent`.
- Contiene `CREATE DATABASE` y `\connect`, instrucciones específicas de `psql` que no pueden ejecutarse directamente desde un cliente SQL genérico.
- Incluye datos de demostración: módulo inicial, administrador inicial y fechas de demostración.
- La contraseña del administrador no debe quedar codificada en el esquema ni en scripts.

### Especificación técnica

El documento `Especificacion_Tecnica_Control_Asistencia.md` describe conceptualmente una solución con Django. Esa descripción no coincide con el código real de backend y frontend. Para el despliegue se debe tomar como fuente de verdad el código implementado, no la parte de Django de la especificación.

## 3. Hallazgos críticos

### 3.1 Credenciales AWS en texto plano

Se encontraron credenciales AWS embebidas en proyectos anteriores:

- `tf_stackflow/terraform/main.tf`
- `tf_stackflow/tofu/main.tf`

Riesgos:

- Exposición de credenciales en el historial Git.
- Uso no autorizado de la cuenta.
- Modificación o destrucción de recursos.
- Generación de costos.

Acciones requeridas:

- Revocar o rotar las claves expuestas.
- Revisar el historial Git y los registros de CloudTrail.
- No reutilizar las claves.
- No copiar los archivos ni sus valores a este repositorio.

Estas acciones no se ejecutaron en la Etapa 2 y requieren autorización y un procedimiento separado.

### 3.2 Usuario IAM con privilegios administrativos

Se identificó un usuario IAM con `AdministratorAccess` y una access key activa.

Riesgos:

- Un único usuario con control total de la cuenta.
- Mayor impacto si la clave se filtra.
- Dificultad para auditar acciones.

Acciones requeridas:

- Reemplazar el uso de usuarios y access keys por roles IAM y OIDC.
- Aplicar mínimo privilegio.
- Revisar y rotar la access key existente.
- No modificar ni eliminar el usuario sin un procedimiento aprobado.

### 3.3 Security Groups permisivos

Los Security Groups de los proyectos anteriores permiten SSH y HTTP desde `0.0.0.0/0`.

Riesgos:

- Exposición de administración a Internet.
- Fuerza bruta y intentos de explotación.
- Difícil justificar en un entorno productivo.

La nueva arquitectura no abre SSH y restringe el backend al Security Group del frontend.

### 3.4 Estado y recursos existentes

El proyecto `terraform-stackoverflow-01` tiene estado remoto en S3 y recursos existentes. Debe permanecer intacto.

No se reutilizarán:

- Instancias EC2.
- Security Groups.
- Key pairs.
- VPC por defecto.
- Estados remotos.
- Nombres de recursos de los proyectos anteriores.

## 4. Recursos AWS observados

La auditoría de solo lectura encontró, entre otros:

- Instancias EC2 detenidas de pruebas anteriores.
- Un key pair anterior.
- Un bucket S3 de estado de Terraform con versionado, cifrado y acceso público bloqueado.
- Una tabla DynamoDB para bloqueo de estado.
- Un bucket de plantillas CloudFormation.
- Usuarios y roles IAM de proyectos previos.
- Sin proveedor OIDC de GitHub configurado.
- Sin stacks CloudFormation activos.
- Sin Elastic IP ni hosted zones de Route 53 para este proyecto.

No se incluyen identificadores sensibles en este documento. Cualquier reutilización de recursos existentes requerirá una revisión y autorización específicas.

## 5. Componentes de infraestructura revisados

### Terraform anterior

- Usaba Ubuntu en lugar de Amazon Linux 2023.
- AMI fija.
- Sin user-data.
- Sin IAM instance profile.
- Security Groups con SSH y HTTP abiertos.
- Estado remoto existente.

No se reutiliza como base de despliegue. Solo se tomó como referencia de configuración de backend de estado.

### Pulumi anterior

- Template de “hola mundo” con AL2023, VPC y Nginx.
- Útil como referencia conceptual.
- No implementa Secrets Manager, IAM de mínimo privilegio, SSM ni la arquitectura de dos instancias.
- La configuración observada apuntaba a una región distinta de la instancia existente; existe riesgo de deriva si se reutiliza.

### CloudFormation anterior

- Plantillas de demostración con AL2023, rol SSM y sin SSH.
- Patrones reutilizables conceptualmente.
- No implementan la arquitectura completa.

## 6. Riesgos heredados y pendientes

| Riesgo | Estado | Acción |
| --- | --- | --- |
| Credenciales AWS expuestas | Abierto | Revocar/rotar y revisar historial |
| Usuario IAM administrador | Abierto | Reemplazar por roles y OIDC |
| SSH abierto en SGs antiguos | Abierto | No reutilizar; revisar recursos existentes |
| Recursos de prueba detenidos | Abierto | No reutilizar; decidir limpieza en otra tarea |
| Estados remotos de proyectos anteriores | Abierto | No modificar |
| Login de estudiante sin contraseña | Abierto | Revisar en backend |
| Persistencia solo en volumen raíz | Aceptado con condición | Implementar backups y pruebas de restauración |
| IP pública del backend | Aceptado con condición | Security Groups estrictos y revisión futura |
| IP pública dinámica del frontend | Aceptado con condición | Documentar cambio de IP y considerar dominio/EIP en el futuro |

## 7. Conclusiones para el despliegue

- La arquitectura debe construirse desde cero, sin reutilizar los recursos de prueba.
- Los secretos deben gestionarse con Secrets Manager.
- La administración debe usar SSM, no SSH.
- Terraform, Pulumi y CloudFormation deben ser alternativas independientes.
- Cloud-Init debe ser compartido y versionado.
- La Etapa 2 no debe crear recursos ni ejecutar despliegues.
