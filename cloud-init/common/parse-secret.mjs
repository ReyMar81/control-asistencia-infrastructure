import { readFileSync } from 'node:fs';

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(2);
}

let secret;
try {
  secret = JSON.parse(readFileSync(0, 'utf8'));
} catch {
  fail('El secreto no es JSON valido.');
}

if (!secret || typeof secret !== 'object' || Array.isArray(secret)) {
  fail('El secreto debe ser un objeto JSON.');
}

const required = ['DATABASE_URL', 'JWT_SECRET', 'ADMIN_PASSWORD'];
for (const key of required) {
  if (typeof secret[key] !== 'string' || secret[key].length === 0) {
    fail(`Campo obligatorio ausente o invalido: ${key}.`);
  }
  if (/[\r\n\0]/.test(secret[key])) {
    fail(`El campo ${key} contiene caracteres de control no permitidos.`);
  }
}

if (secret.JWT_SECRET.length < 32) {
  fail('JWT_SECRET debe tener al menos 32 caracteres.');
}
if (secret.ADMIN_PASSWORD.length < 12) {
  fail('ADMIN_PASSWORD debe tener al menos 12 caracteres.');
}

let databaseUrl;
try {
  databaseUrl = new URL(secret.DATABASE_URL);
} catch {
  fail('DATABASE_URL no es una URL valida.');
}

if (!['postgres:', 'postgresql:'].includes(databaseUrl.protocol)) {
  fail('DATABASE_URL debe usar postgres:// o postgresql://.');
}

let user;
let password;
let database;
try {
  user = decodeURIComponent(databaseUrl.username);
  password = decodeURIComponent(databaseUrl.password);
  database = decodeURIComponent(databaseUrl.pathname.replace(/^\/+/, ''));
} catch {
  fail('DATABASE_URL contiene valores codificados invalidos.');
}

const host = databaseUrl.hostname;
const port = databaseUrl.port || '5432';
if (!['localhost', '127.0.0.1', '::1'].includes(host)) {
  fail('DATABASE_URL debe apuntar a localhost.');
}
if (port !== '5432') {
  fail('DATABASE_URL debe usar el puerto 5432.');
}
if (!/^[A-Za-z_][A-Za-z0-9_]{0,62}$/.test(user)) {
  fail('El usuario de DATABASE_URL no es valido.');
}
if (!/^[A-Za-z_][A-Za-z0-9_]{0,62}$/.test(database)) {
  fail('El nombre de base de datos de DATABASE_URL no es valido.');
}
if (!password) {
  fail('DATABASE_URL debe incluir una contrasena.');
}

const values = [
  secret.DATABASE_URL,
  secret.JWT_SECRET,
  secret.ADMIN_PASSWORD,
  user,
  password,
  host,
  port,
  database,
];

process.stdout.write(values.join('\0'));
