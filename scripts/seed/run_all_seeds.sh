#!/bin/bash
# =============================================================================
# GymPro — Runner de seeding completo
# =============================================================================
# Ejecuta la migración SQL y ambos scripts de seeding en orden.
#
# USO:
#   chmod +x scripts/seed/run_all_seeds.sh
#   ./scripts/seed/run_all_seeds.sh
#
# VARIABLES REQUERIDAS:
#   SUPABASE_URL          — ej: https://abcdefgh.supabase.co
#   SUPABASE_SERVICE_KEY  — Service Role Key (empieza con eyJ...)
#   SUPABASE_DB_URL       — Cadena de conexión psql (opcional, para migración SQL directa)
#
# NOTA: Si no tienes psql disponible, ejecuta 02_fitness_service_db.sql
#       manualmente en el SQL Editor de Supabase.
# =============================================================================

set -e  # Abortar si cualquier comando falla

# Colores ANSI para la terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║  GymPro — Pipeline de Seeding Completo                 ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ─── Verificar variables de entorno ─────────────────────────────────────────
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SERVICE_KEY" ]; then
  echo -e "${RED}❌ Error: SUPABASE_URL y SUPABASE_SERVICE_KEY son requeridas.${RESET}"
  echo ""
  echo "   Expórtalas antes de ejecutar:"
  echo "   export SUPABASE_URL='https://XXXX.supabase.co'"
  echo "   export SUPABASE_SERVICE_KEY='eyJhbGci...'"
  echo ""
  exit 1
fi

echo -e "${GREEN}✅ Variables de entorno detectadas.${RESET}"
echo -e "   URL: ${SUPABASE_URL}"
echo ""

# ─── Paso 1: Migración SQL (opcional si ya se ejecutó) ───────────────────────
echo -e "${BOLD}═══ PASO 1: Migración SQL (fitness_service_db) ═══${RESET}"

if [ -n "$SUPABASE_DB_URL" ]; then
  echo "📋 Ejecutando 02_fitness_service_db.sql via psql..."
  psql "$SUPABASE_DB_URL" -f "docs/database/schemas/02_fitness_service_db.sql"
  echo -e "${GREEN}✅ Migración SQL ejecutada.${RESET}"
else
  echo -e "${YELLOW}⚠️  SUPABASE_DB_URL no definida.${RESET}"
  echo "   Ejecuta manualmente en Supabase SQL Editor:"
  echo "   docs/database/schemas/02_fitness_service_db.sql"
  echo ""
  read -p "   ¿Ya ejecutaste el SQL? Presiona ENTER para continuar o Ctrl+C para abortar..."
fi
echo ""

# ─── Paso 2: Seeding de Ejercicios (wger) ────────────────────────────────────
echo -e "${BOLD}═══ PASO 2: Seeding — Ejercicios (wger API) ═══${RESET}"
echo ""
node scripts/seed/seed_ejercicios_wger.js
echo ""
echo -e "${GREEN}✅ Seeding de ejercicios completado.${RESET}"
echo ""

# ─── Paso 3: Seeding de Alimentos (Open Food Facts) ──────────────────────────
echo -e "${BOLD}═══ PASO 3: Seeding — Alimentos (Open Food Facts) ═══${RESET}"
echo ""

# Verificar si existe un archivo JSONL local
JSONL_PATH="./openfoodfacts-products.jsonl"
if [ -f "$JSONL_PATH" ]; then
  echo "📁 Archivo JSONL detectado: $JSONL_PATH"
  echo "   Usando modo ARCHIVO (más rápido y completo)..."
  echo ""
  node scripts/seed/seed_alimentos_off.js --file "$JSONL_PATH"
else
  echo "🌐 Archivo JSONL no encontrado. Usando modo API..."
  echo -e "${YELLOW}   Tip: Para resultados más completos, descarga el dump:${RESET}"
  echo "   wget 'https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz'"
  echo "   gunzip openfoodfacts-products.jsonl.gz"
  echo ""
  node scripts/seed/seed_alimentos_off.js --api
fi

echo ""
echo -e "${GREEN}✅ Seeding de alimentos completado.${RESET}"
echo ""

# ─── Resumen final ────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║  🎉 Pipeline de Seeding COMPLETADO                     ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "   Base de datos lista para GymPro:"
echo "   • fitness_service_db.catalogo_ejercicios  — Ejercicios de wger"
echo "   • fitness_service_db.catalogo_alimentos   — Alimentos de OFX"
echo ""
echo -e "${YELLOW}   Próximo paso: Verificar en Supabase Table Editor.${RESET}"
echo ""
