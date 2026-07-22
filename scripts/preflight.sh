#!/usr/bin/env bash
# =====================================================================
# PREFLIGHT de GymPro — diagnóstico del monorepo.
#
#   ./scripts/preflight.sh            todos los servicios
#   ./scripts/preflight.sh ai-service un servicio concreto
#
# NO se detiene al primer fallo: queremos el cuadro completo.
# Comprueba los patrones que ya nos han roto el arranque una vez:
#   · nombres de cola BullMQ con ":"
#   · modelos de IA retirados por el proveedor
#   · listeners de proceso duplicados (Winston)
#   · contenedores caídos o en crash loop
# =====================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONLY="${1:-}"

G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; B='\033[1m'; N='\033[0m'
PASS=0; FAIL=0; WARN=0
PROBLEMS=()

ok()   { echo -e "  ${G}✓${N} $1"; PASS=$((PASS+1)); }
bad()  { echo -e "  ${R}✗${N} $1"; FAIL=$((FAIL+1)); PROBLEMS+=("$1${2:+ → $2}"); }
warn() { echo -e "  ${Y}!${N} $1"; WARN=$((WARN+1)); }
sec()  { echo; echo -e "${B}$1${N}"; }

SERVICES=()
for d in "$ROOT"/services/*/; do
  s=$(basename "$d")
  [ -f "$d/package.json" ] || continue
  [ -n "$ONLY" ] && [ "$s" != "$ONLY" ] && continue
  SERVICES+=("$s")
done

# ---------------------------------------------------------------------
sec "1. Herramientas"

if command -v node >/dev/null; then
  MAJ=$(node -p "process.versions.node.split('.')[0]")
  [ "$MAJ" -ge 20 ] && ok "node $(node -v)" || bad "node $(node -v) < 20"
else
  bad "node no instalado"
fi

if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  ok "docker operativo"
  HAS_DOCKER=1
else
  warn "docker no disponible: se omiten los checks de contenedores"
  HAS_DOCKER=0
fi

# ---------------------------------------------------------------------
sec "2. Contenedores"

if [ "$HAS_DOCKER" = "1" ]; then
  for c in $(docker ps -a --filter "name=gympro-" --format '{{.Names}}' | sort); do
    status=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
    restarts=$(docker inspect -f '{{.RestartCount}}' "$c" 2>/dev/null)
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$c" 2>/dev/null)

    if [ "$status" != "running" ]; then
      bad "$c está '$status'" "docker logs --tail=30 $c"
    elif [ "${restarts:-0}" -gt 5 ]; then
      # Un RestartCount alto es la firma de un crash loop, aunque ahora
      # mismo el contenedor aparezca 'running'.
      bad "$c con $restarts reinicios (crash loop)" "docker logs --tail=50 $c"
    elif [ "$health" = "unhealthy" ]; then
      bad "$c unhealthy"
    else
      ok "$c ($status, health=$health, reinicios=$restarts)"
    fi
  done

  # Para cada contenedor que NO esté sano, volcar el final de sus logs.
  # Adivinar el formato del mensaje de error no funciona (cada servicio
  # loguea distinto): es más útil enseñar las últimas líneas útiles y
  # dejar que las lea una persona.
  for c in $(docker ps -a --filter "name=gympro-" --format '{{.Names}}' | sort); do
    status=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
    restarts=$(docker inspect -f '{{.RestartCount}}' "$c" 2>/dev/null)
    [ "$status" = "running" ] && [ "${restarts:-0}" -le 5 ] && continue

    echo
    echo -e "  ${Y}── últimas líneas de $c ──${N}"
    # Se filtran los INFO de arranque, que en un crash loop son ruido:
    # lo que interesa es la excepción, no los middlewares que sí cargaron.
    docker logs --tail=120 "$c" 2>&1 \
      | grep -viE "^\s*$|info:|^\s*\{|^\s*\}|^\s*\"|^\s*\]|^\s*\[$" \
      | tail -12 | sed 's/^/      /'
  done
fi

# ---------------------------------------------------------------------
sec "3. Colas BullMQ"

# BullMQ >= v4 rechaza nombres con ":" (lo usa como separador de claves).
# Fue lo que tumbó fitness-service en bucle.
QBAD=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  bad "nombre de cola con ':' → $line" "usa la opción prefix"
  QBAD=1
done < <(grep -rn --include=*.js --exclude-dir=node_modules \
           -E "(QUEUE_NAME|queueName)\s*[:=]\s*['\"][^'\"]*:" \
           "$ROOT/services" "$ROOT/packages_shared" 2>/dev/null)
[ "$QBAD" = "0" ] && ok "ningún nombre de cola contiene ':'"

# Queue y Worker deben compartir prefix o los jobs no se procesan
# (y no hay ningún error: fallo silencioso).
for f in $(grep -rl "new Worker(" --include=*.js --exclude-dir=node_modules "$ROOT/services" 2>/dev/null); do
  if ! grep -q "prefix:" "$f"; then
    warn "$(basename "$f") crea un Worker sin 'prefix' — verifica que la Queue tampoco lo use"
  fi
done

# ---------------------------------------------------------------------
sec "4. Logger compartido"

LOG="$ROOT/packages_shared/security/logger.js"
if grep -q "loggerCache" "$LOG" 2>/dev/null; then
  ok "logger cacheado (no duplica listeners de proceso)"
else
  bad "logger sin caché: cada createServiceLogger añade listeners a process" \
      "provoca MaxListenersExceededWarning"
fi

if [ "$HAS_DOCKER" = "1" ]; then
  for c in $(docker ps --filter "name=gympro-" --format '{{.Names}}'); do
    if docker logs --tail=100 "$c" 2>&1 | grep -q "MaxListenersExceededWarning"; then
      bad "$c sigue emitiendo MaxListenersExceededWarning" "¿reconstruiste la imagen? docker compose up -d --build"
    fi
  done
fi

# ---------------------------------------------------------------------
sec "5. Servicios"

for s in "${SERVICES[@]}"; do
  d="$ROOT/services/$s"
  echo -e "  ${B}$s${N}"

  [ -f "$d/.env" ] && echo -e "    ${G}✓${N} .env presente" && PASS=$((PASS+1)) \
                   || { echo -e "    ${R}✗${N} falta .env"; FAIL=$((FAIL+1)); PROBLEMS+=("$s: falta .env"); }

  [ -d "$d/node_modules" ] && echo -e "    ${G}✓${N} node_modules" && PASS=$((PASS+1)) \
                           || { echo -e "    ${R}✗${N} sin node_modules"; FAIL=$((FAIL+1)); PROBLEMS+=("$s: npm install"); }

  # Dependencias con problemas conocidos.
  if [ -f "$d/package.json" ]; then
    node -e "
      const p = require('$d/package.json');
      const deps = { ...p.dependencies, ...p.devDependencies };
      const out = [];
      for (const [k, v] of Object.entries(deps)) {
        const ver = v.replace(/^[\^~]/, '');
        if (k === 'multer' && ver.startsWith('1.')) out.push('multer ' + v + ' deprecado (CVEs) → ^2.0.0');
        if (k === '@google/generative-ai') out.push(k + ' es el SDK legacy → @google/genai');
        if (k === 'request') out.push('request está deprecado desde 2020');
      }
      out.forEach(o => console.log('    ! ' + o));
    " 2>/dev/null
  fi
done

# ---------------------------------------------------------------------
sec "6. Modelos de IA"

AIENV="$ROOT/services/ai-service/.env"
if [ -f "$AIENV" ]; then
  # NO se usa `source`: los .env con valores que contienen espacios sin
  # comillas (p. ej. AI_SYSTEM_PERSONA) hacen que bash intente
  # ejecutarlos ("GymBot,: instrucción no encontrada") y la variable
  # nunca se carga, dando un falso "no se pudo consultar".
  read_env() {
    sed -n "s/^[[:space:]]*${1}=//p" "$AIENV" | head -1 \
      | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" -e 's/[[:space:]]*$//'
  }
  GEMINI_API_KEY=$(read_env GEMINI_API_KEY)
  GEMINI_MODEL=$(read_env GEMINI_MODEL)
  GEMINI_MODEL_PRO=$(read_env GEMINI_MODEL_PRO)

  if [ -n "${GEMINI_API_KEY:-}" ]; then
    CAT=$(curl -s --max-time 8 \
      "https://generativelanguage.googleapis.com/v1beta/models?key=${GEMINI_API_KEY}" 2>/dev/null)

    if echo "$CAT" | grep -q 'API_KEY_INVALID\|API key not valid'; then
      bad "GEMINI_API_KEY inválida (la API responde API_KEY_INVALID)" \
          "genera una nueva en aistudio.google.com/apikey"
    elif echo "$CAT" | grep -q '"models"'; then
      ok "catálogo de Gemini accesible"
      for var in GEMINI_MODEL GEMINI_MODEL_PRO; do
        m="${!var:-}"
        [ -z "$m" ] && continue
        if echo "$CAT" | grep -q "\"models/$m\""; then
          ok "$var=$m existe"
        else
          bad "$var=$m NO existe (retirado o sin acceso)" "el servicio dará 404 en cada petición"
        fi
      done
      echo "    modelos flash/lite disponibles:"
      echo "$CAT" | grep -oP '"name": "models/\K[^"]+' | grep -iE 'flash|lite' \
        | head -8 | sed 's/^/      · /'
    else
      warn "no se pudo consultar el catálogo de Gemini (¿clave o red?)"
    fi
  else
    warn "GEMINI_API_KEY no definida"
  fi
else
  warn "services/ai-service/.env no existe"
fi

# ---------------------------------------------------------------------
sec "7. Redis"

if [ "$HAS_DOCKER" = "1" ] && docker ps --format '{{.Names}}' | grep -q gympro-redis; then
  docker exec gympro-redis redis-cli ping >/dev/null 2>&1 \
    && ok "Redis responde" || bad "Redis no responde"

  # Solo informativo: RediSearch hace falta para el caché semántico,
  # que todavía no está portado.
  if docker exec gympro-redis redis-cli MODULE LIST 2>/dev/null | grep -qi search; then
    ok "RediSearch cargado (caché semántico posible)"
  else
    warn "sin RediSearch — necesario si portas el caché semántico"
  fi

  keys=$(docker exec gympro-redis redis-cli DBSIZE 2>/dev/null | tr -dc '0-9')
  echo "    claves en Redis: ${keys:-?}"
fi

# ---------------------------------------------------------------------
echo
echo "════════════════════════════════════════════════════"
echo -e "  ${G}$PASS OK${N}   ${R}$FAIL fallos${N}   ${Y}$WARN avisos${N}"
echo "════════════════════════════════════════════════════"

if [ ${#PROBLEMS[@]} -gt 0 ]; then
  echo
  echo "Hay que arreglar:"
  printf '  • %s\n' "${PROBLEMS[@]}"
  exit 1
fi
echo
echo "Sin problemas detectados."
