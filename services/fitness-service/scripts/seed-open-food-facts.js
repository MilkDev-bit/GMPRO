#!/usr/bin/env node
/**
 * @file services/fitness-service/scripts/seed-open-food-facts.js
 * @description Siembra `catalogo_alimentos` con un set curado de alimentos comunes
 *   en español (macros por 100 g). Da un catálogo LOCAL, instantáneo y offline para
 *   el buscador de alimentos / selector de ingredientes, sin depender de que la API
 *   de Open Food Facts esté rápida (esa queda como cola larga en el controlador).
 *
 * DATOS
 *   Valores nutricionales por 100 g de fuentes estándar (USDA/BEDCA), redondeados.
 *   No son productos de marca: son ALIMENTOS BASE (pollo, arroz, brócoli…), que es
 *   justo lo que el socio quiere elegir como "ingredientes que tengo".
 *
 * IDEMPOTENTE
 *   `codigo_barras` (PK) se deriva de forma estable del nombre → re-correr no duplica.
 *
 * USO
 *   SEED_DATABASE_URL="postgres://..." node services/fitness-service/scripts/seed-open-food-facts.js
 *   ... --dry-run     (no escribe, solo muestra el resumen)
 *   ... --limit 20
 *
 * VARIABLES
 *   REQUERIDA: SEED_DATABASE_URL (o SUPABASE_DB_URL / DATABASE_URL)
 *   OPCIONAL:  SEED_DB_SCHEMA (def: fitness_service_db)
 */

'use strict';

try { require('dotenv').config({ path: `${__dirname}/../.env` }); } catch { /* opcional */ }

const args = process.argv.slice(2);
const flag = (n) => args.includes(`--${n}`);
const flagVal = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 && args[i + 1] ? args[i + 1] : d; };

const CONFIG = {
  // Reutiliza la MISMA conexión del fitness-service (FITNESS_DATABASE_URL, ya en el .env).
  dbUrl: process.env.SEED_DATABASE_URL
      || process.env.FITNESS_DATABASE_URL
      || process.env.SUPABASE_DB_URL
      || process.env.DATABASE_URL
      || '',
  dbSchema: process.env.SEED_DB_SCHEMA || 'fitness_service_db',
  table: 'catalogo_alimentos',
  dryRun: flag('dry-run'),
  limit: parseInt(flagVal('limit', '0'), 10) || 0,
};

const ts = () => new Date().toISOString().slice(11, 19);
const log = {
  info: (m) => console.log(`[${ts()}] ${m}`),
  ok: (m) => console.log(`[${ts()}] ✅ ${m}`),
  err: (m) => console.error(`[${ts()}] ❌ ${m}`),
  step: (m) => console.log(`\n[${ts()}] ── ${m} ──`),
};

// ─── Dataset curado (por 100 g): [nombre, categoria, kcal, prot, carbs, grasa, fibra] ─
const FOODS = [
  // Carnes y aves
  ['Pechuga de pollo (sin piel)', 'Carnes', 165, 31, 0, 3.6, 0],
  ['Muslo de pollo (sin piel)', 'Carnes', 177, 24, 0, 8.4, 0],
  ['Carne de res molida (magra)', 'Carnes', 176, 20, 0, 10, 0],
  ['Bistec de res (magro)', 'Carnes', 187, 27, 0, 8, 0],
  ['Lomo de cerdo', 'Carnes', 143, 26, 0, 3.5, 0],
  ['Pechuga de pavo', 'Carnes', 135, 30, 0, 1, 0],
  ['Jamón de pavo', 'Carnes', 104, 17, 3, 3, 0],
  ['Chuleta de cerdo', 'Carnes', 231, 25, 0, 14, 0],
  // Pescados y mariscos
  ['Atún en agua', 'Pescados', 116, 26, 0, 1, 0],
  ['Salmón', 'Pescados', 208, 20, 0, 13, 0],
  ['Tilapia', 'Pescados', 128, 26, 0, 2.7, 0],
  ['Camarón', 'Pescados', 99, 24, 0.2, 0.3, 0],
  ['Sardina en agua', 'Pescados', 208, 25, 0, 11, 0],
  ['Merluza', 'Pescados', 90, 18, 0, 2, 0],
  // Huevos y lácteos
  ['Huevo entero', 'Huevos y lácteos', 155, 13, 1.1, 11, 0],
  ['Clara de huevo', 'Huevos y lácteos', 52, 11, 0.7, 0.2, 0],
  ['Leche entera', 'Huevos y lácteos', 61, 3.2, 4.8, 3.3, 0],
  ['Leche descremada', 'Huevos y lácteos', 34, 3.4, 5, 0.1, 0],
  ['Yogur griego natural', 'Huevos y lácteos', 59, 10, 3.6, 0.4, 0],
  ['Yogur natural', 'Huevos y lácteos', 61, 3.5, 4.7, 3.3, 0],
  ['Queso panela', 'Huevos y lácteos', 215, 18, 3, 14, 0],
  ['Queso fresco', 'Huevos y lácteos', 145, 12, 3.5, 9, 0],
  ['Requesón (cottage)', 'Huevos y lácteos', 98, 11, 3.4, 4.3, 0],
  ['Queso cheddar', 'Huevos y lácteos', 403, 25, 1.3, 33, 0],
  // Cereales, granos y panes
  ['Arroz blanco cocido', 'Cereales', 130, 2.7, 28, 0.3, 0.4],
  ['Arroz integral cocido', 'Cereales', 123, 2.7, 26, 1, 1.6],
  ['Avena en hojuelas', 'Cereales', 389, 17, 66, 7, 11],
  ['Pan integral', 'Cereales', 247, 13, 41, 3.4, 7],
  ['Pan blanco', 'Cereales', 265, 9, 49, 3.2, 2.7],
  ['Tortilla de maíz', 'Cereales', 218, 5.7, 45, 2.5, 6],
  ['Tortilla de harina', 'Cereales', 304, 8, 51, 7, 3],
  ['Pasta cocida', 'Cereales', 158, 5.8, 31, 0.9, 1.8],
  ['Quinoa cocida', 'Cereales', 120, 4.4, 21, 1.9, 2.8],
  ['Cereal de maíz', 'Cereales', 357, 7, 84, 0.9, 3],
  ['Harina de avena', 'Cereales', 404, 15, 66, 9, 10],
  // Legumbres
  ['Frijol negro cocido', 'Legumbres', 132, 8.9, 24, 0.5, 8.7],
  ['Frijol pinto cocido', 'Legumbres', 143, 9, 26, 0.7, 9],
  ['Lenteja cocida', 'Legumbres', 116, 9, 20, 0.4, 7.9],
  ['Garbanzo cocido', 'Legumbres', 164, 8.9, 27, 2.6, 7.6],
  ['Soya (edamame)', 'Legumbres', 121, 12, 9, 5, 5],
  // Verduras
  ['Brócoli', 'Verduras', 34, 2.8, 7, 0.4, 2.6],
  ['Espinaca', 'Verduras', 23, 2.9, 3.6, 0.4, 2.2],
  ['Zanahoria', 'Verduras', 41, 0.9, 10, 0.2, 2.8],
  ['Jitomate', 'Verduras', 18, 0.9, 3.9, 0.2, 1.2],
  ['Lechuga', 'Verduras', 15, 1.4, 2.9, 0.2, 1.3],
  ['Pepino', 'Verduras', 15, 0.7, 3.6, 0.1, 0.5],
  ['Calabacita', 'Verduras', 17, 1.2, 3.1, 0.3, 1],
  ['Pimiento', 'Verduras', 31, 1, 6, 0.3, 2.1],
  ['Champiñón', 'Verduras', 22, 3.1, 3.3, 0.3, 1],
  ['Cebolla', 'Verduras', 40, 1.1, 9, 0.1, 1.7],
  ['Chayote', 'Verduras', 19, 0.8, 4.5, 0.1, 1.7],
  ['Nopal', 'Verduras', 16, 1.3, 3.3, 0.1, 2.2],
  ['Ejote', 'Verduras', 31, 1.8, 7, 0.2, 3.4],
  ['Betabel', 'Verduras', 43, 1.6, 10, 0.2, 2.8],
  // Tubérculos
  ['Papa cocida', 'Tubérculos', 87, 1.9, 20, 0.1, 1.8],
  ['Camote', 'Tubérculos', 86, 1.6, 20, 0.1, 3],
  ['Yuca', 'Tubérculos', 160, 1.4, 38, 0.3, 1.8],
  // Frutas
  ['Plátano', 'Frutas', 89, 1.1, 23, 0.3, 2.6],
  ['Manzana', 'Frutas', 52, 0.3, 14, 0.2, 2.4],
  ['Fresa', 'Frutas', 32, 0.7, 7.7, 0.3, 2],
  ['Naranja', 'Frutas', 47, 0.9, 12, 0.1, 2.4],
  ['Papaya', 'Frutas', 43, 0.5, 11, 0.3, 1.7],
  ['Piña', 'Frutas', 50, 0.5, 13, 0.1, 1.4],
  ['Mango', 'Frutas', 60, 0.8, 15, 0.4, 1.6],
  ['Uva', 'Frutas', 69, 0.7, 18, 0.2, 0.9],
  ['Sandía', 'Frutas', 30, 0.6, 8, 0.2, 0.4],
  ['Melón', 'Frutas', 34, 0.8, 8, 0.2, 0.9],
  ['Arándano', 'Frutas', 57, 0.7, 14, 0.3, 2.4],
  ['Kiwi', 'Frutas', 61, 1.1, 15, 0.5, 3],
  ['Durazno', 'Frutas', 39, 0.9, 10, 0.3, 1.5],
  ['Pera', 'Frutas', 57, 0.4, 15, 0.1, 3.1],
  // Frutos secos y semillas
  ['Almendra', 'Frutos secos', 579, 21, 22, 50, 12.5],
  ['Cacahuate', 'Frutos secos', 567, 26, 16, 49, 8.5],
  ['Nuez', 'Frutos secos', 654, 15, 14, 65, 6.7],
  ['Pistache', 'Frutos secos', 560, 20, 28, 45, 10],
  ['Semilla de chía', 'Frutos secos', 486, 17, 42, 31, 34],
  ['Semilla de girasol', 'Frutos secos', 584, 21, 20, 51, 8.6],
  ['Crema de cacahuate', 'Frutos secos', 588, 25, 20, 50, 6],
  // Grasas y aceites
  ['Aceite de oliva', 'Grasas', 884, 0, 0, 100, 0],
  ['Aguacate', 'Grasas', 160, 2, 9, 15, 7],
  ['Mantequilla', 'Grasas', 717, 0.9, 0.1, 81, 0],
  ['Aceite de coco', 'Grasas', 862, 0, 0, 100, 0],
  // Suplementos y otros
  ['Proteína de suero (whey)', 'Suplementos', 400, 80, 8, 6, 0],
  ['Miel', 'Otros', 304, 0.3, 82, 0, 0.2],
  ['Chocolate amargo 70%', 'Otros', 598, 7.8, 46, 43, 11],
];

// ─── pg (reutiliza el del propio fitness-service) ─────────────────────────────
let _pool = null;
function pool() {
  if (_pool) return _pool;
  const { Pool } = require('pg');
  const connectionString = CONFIG.dbUrl.replace(/[?&]sslmode=[^&]+/i, '');
  _pool = new Pool({ connectionString, ssl: { rejectUnauthorized: false }, max: 4 });
  return _pool;
}
const closePool = async () => { if (_pool) { try { await _pool.end(); } catch { /* noop */ } _pool = null; } };

// codigo_barras estable derivado del nombre (djb2), prefijo SEED- (cabe en VARCHAR(30)).
function codeFor(nombre) {
  let h = 5381;
  for (let i = 0; i < nombre.length; i++) h = ((h << 5) + h + nombre.charCodeAt(i)) >>> 0;
  return `SEED-${h}`;
}
const strip = (s) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

const COLS = [
  'codigo_barras', 'nombre', 'nombre_generico', 'marca', 'categoria',
  'calorias_100g', 'proteinas_100g', 'carbohidratos_100g', 'grasas_100g', 'fibra_100g',
  'porcion_gramos', 'idioma_nombre',
];

function rowFor([nombre, categoria, kcal, prot, carbs, grasa, fibra]) {
  return {
    codigo_barras: codeFor(nombre),
    nombre,
    nombre_generico: strip(nombre).slice(0, 200),
    marca: 'Genérico',
    categoria,
    calorias_100g: kcal,
    proteinas_100g: prot,
    carbohidratos_100g: carbs,
    grasas_100g: grasa,
    fibra_100g: fibra,
    porcion_gramos: 100,
    idioma_nombre: 'es',
  };
}

async function upsert(rows) {
  if (!rows.length) return 0;
  const values = [];
  const tuples = rows.map((r, i) => {
    const base = i * COLS.length;
    const ph = COLS.map((_, j) => `$${base + j + 1}`);
    for (const c of COLS) values.push(r[c] ?? null);
    return `(${ph.join(', ')})`;
  });
  const updateSet = COLS.filter((c) => c !== 'codigo_barras')
    .map((c) => `"${c}" = EXCLUDED."${c}"`).join(', ');
  const sql = `
    INSERT INTO ${CONFIG.dbSchema}.${CONFIG.table} (${COLS.map((c) => `"${c}"`).join(', ')})
    VALUES ${tuples.join(', ')}
    ON CONFLICT (codigo_barras) DO UPDATE SET ${updateSet}`;
  await pool().query(sql, values);
  return rows.length;
}

async function main() {
  if (!CONFIG.dryRun && !CONFIG.dbUrl) {
    log.err('Falta SEED_DATABASE_URL (connection string de Postgres de Supabase).');
    process.exit(1);
  }
  let data = FOODS;
  if (CONFIG.limit) data = data.slice(0, CONFIG.limit);
  const rows = data.map(rowFor);

  log.step('Seed de catalogo_alimentos (dataset curado)');
  log.info(`Alimentos: ${rows.length} · Tabla: ${CONFIG.table} · ${CONFIG.dryRun ? 'DRY-RUN' : 'ESCRITURA'}`);

  if (CONFIG.dryRun) {
    for (const r of rows.slice(0, 8)) log.info(`  ${r.nombre} — ${r.calorias_100g} kcal · P${r.proteinas_100g} C${r.carbohidratos_100g} G${r.grasas_100g}`);
    log.info(`  … (${rows.length} en total)`);
    log.ok('Dry-run completado (no se escribió).');
    return;
  }

  let done = 0;
  for (let i = 0; i < rows.length; i += 50) {
    done += await upsert(rows.slice(i, i + 50));
    log.info(`  Upsertados ${done}/${rows.length}`);
  }
  log.ok(`Seed completado: ${done} alimentos.`);
  await closePool();
}

main().catch(async (err) => {
  log.err(`Error fatal: ${err.message}`);
  await closePool();
  process.exit(1);
});
