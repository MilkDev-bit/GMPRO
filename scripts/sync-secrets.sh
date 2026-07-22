#!/usr/bin/env bash
# =====================================================================
# Genera y propaga los secretos COMPARTIDOS a todos los .env.
#
#   ./scripts/sync-secrets.sh              genera nuevos y los propaga
#   ./scripts/sync-secrets.sh --from auth-service   usa los de ese servicio
#   ./scripts/sync-secrets.sh --dry-run    solo muestra qué haría
#
# QUÉ TOCA:
#   JWT_SECRET e INTER_SERVICE_SECRET — son secretos compartidos y deben
#   ser idénticos en todos los servicios para que la autenticación entre
#   ellos funcione.
#
# QUÉ NO TOCA:
#   SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY y demás credenciales de
#   terceros: no se pueden generar, hay que copiarlas de su panel. El
#   script te dice cuáles faltan pero no las inventa.
#
# SEGURIDAD:
#   Hace copia de seguridad de cada .env antes de tocarlo.
#   ⚠ Rotar JWT_SECRET invalida todas las sesiones activas: en
#   producción hazlo en ventana de mantenimiento.
# =====================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G='\033[0;32m'; Y='\033[0;33m'; B='\033[1m'; N='\033[0m'

DRY_RUN=0
FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --from)    FROM="$2"; shift 2 ;;
    *) echo "Opción desconocida: $1"; exit 1 ;;
  esac
done

read_env() {
  sed -n "s/^[[:space:]]*${2}=//p" "$1" 2>/dev/null | head -1 \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" -e 's/[[:space:]]*$//'
}

# ---------------------------------------------------------------------
# Determinar los valores a propagar
# ---------------------------------------------------------------------
if [ -n "$FROM" ]; then
  SRC="$ROOT/services/$FROM/.env"
  [ -f "$SRC" ] || { echo "No existe $SRC"; exit 1; }
  JWT=$(read_env "$SRC" JWT_SECRET)
  ISS=$(read_env "$SRC" INTER_SERVICE_SECRET)
  [ -z "$JWT" ] && { echo "JWT_SECRET vacío en $FROM"; exit 1; }
  [ -z "$ISS" ] && { echo "INTER_SERVICE_SECRET vacío en $FROM"; exit 1; }
  echo -e "${B}Usando los secretos de $FROM${N}"
else
  # 64 bytes en hex = 128 caracteres: supera el mínimo de 64 con margen.
  JWT=$(openssl rand -hex 64)
  ISS=$(openssl rand -hex 32)
  echo -e "${B}Generando secretos nuevos${N}"
  echo -e "  ${Y}⚠ Esto invalida todas las sesiones activas.${N}"
fi

echo "  JWT_SECRET:           ${#JWT} caracteres"
echo "  INTER_SERVICE_SECRET: ${#ISS} caracteres"
echo

# ---------------------------------------------------------------------
# Propagar
# ---------------------------------------------------------------------
set_var() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    # Se usa | como delimitador y se escapa: los secretos en hex no lo
    # contienen, pero así el script no se rompe con otros valores.
    local esc=${value//|/\\|}
    sed -i.tmp "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$file" && rm -f "$file.tmp"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}

for d in "$ROOT"/services/*/; do
  s=$(basename "$d")
  f="$d/.env"
  [ -f "$f" ] || continue

  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] actualizaría $s"
    continue
  fi

  cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
  set_var "$f" JWT_SECRET "$JWT"
  set_var "$f" INTER_SERVICE_SECRET "$ISS"
  echo -e "  ${G}✓${N} $s actualizado (copia en $(basename "$f").bak.*)"
done

# ---------------------------------------------------------------------
# Credenciales de terceros que hay que poner a mano
# ---------------------------------------------------------------------
echo
echo -e "${B}Credenciales que NO se pueden generar${N}"
echo "  Cópialas de su panel correspondiente:"

for d in "$ROOT"/services/*/; do
  s=$(basename "$d"); f="$d/.env"; [ -f "$f" ] || continue

  srk=$(read_env "$f" SUPABASE_SERVICE_ROLE_KEY)
  if [ -n "$srk" ] && { [[ "$srk" != eyJ* ]] || [ "${#srk}" -lt 100 ]; }; then
    echo "    • $s → SUPABASE_SERVICE_ROLE_KEY (Supabase ▸ Settings ▸ API ▸ service_role)"
  fi

  gk=$(read_env "$f" GEMINI_API_KEY)
  if [ -n "$gk" ] && [ "${#gk}" -lt 30 ]; then
    echo "    • $s → GEMINI_API_KEY (aistudio.google.com/apikey)"
  fi
done

echo
echo "Después:"
echo "  ./scripts/check-secrets.sh      # verificar coherencia"
echo "  docker compose up -d --build    # los .env se leen al arrancar"
