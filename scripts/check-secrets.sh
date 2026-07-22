#!/usr/bin/env bash
# =====================================================================
# Verifica la COHERENCIA de los secretos entre servicios.
#
# POR QUÉ EXISTE:
#   JWT_SECRET e INTER_SERVICE_SECRET son secretos COMPARTIDOS: un
#   servicio firma y otro verifica. Si no son idénticos byte a byte, la
#   autenticación entre servicios falla — pero cada servicio arranca
#   "healthy" por su cuenta y el fallo solo aparece en la primera
#   llamada real. Es el tipo de error que cuesta un día encontrar.
#
#   Este script compara los valores SIN mostrarlos: solo hashes cortos.
#
#   ./scripts/check-secrets.sh
# =====================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; B='\033[1m'; N='\033[0m'
FAIL=0

# Lee una clave de un .env SIN usar `source`: los .env con valores que
# contienen espacios sin comillas (p. ej. AI_SYSTEM_PERSONA) hacen que
# bash intente ejecutarlos.
read_env() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  sed -n "s/^[[:space:]]*${key}=//p" "$file" | head -1 \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" -e 's/[[:space:]]*$//'
}

# Huella corta: permite comparar sin exponer el secreto en pantalla.
fingerprint() {
  printf '%s' "$1" | sha256sum | cut -c1-8
}

SERVICES=()
for d in "$ROOT"/services/*/; do
  s=$(basename "$d")
  [ -f "$d/.env" ] && SERVICES+=("$s")
done

# ---------------------------------------------------------------------
# 1. Secretos que DEBEN coincidir en todos los servicios
# ---------------------------------------------------------------------
for KEY in JWT_SECRET INTER_SERVICE_SECRET SUPABASE_SERVICE_ROLE_KEY SUPABASE_URL; do
  echo
  echo -e "${B}$KEY${N}"

  declare -A seen=()
  for s in "${SERVICES[@]}"; do
    val=$(read_env "$ROOT/services/$s/.env" "$KEY")
    if [ -z "$val" ]; then
      echo -e "  ${R}✗${N} $(printf '%-18s' "$s") VACÍO o ausente"
      FAIL=1
      continue
    fi
    fp=$(fingerprint "$val")
    seen["$fp"]=1
    printf "    %-18s len=%-4s huella=%s\n" "$s" "${#val}" "$fp"
  done

  if [ "${#seen[@]}" -gt 1 ]; then
    echo -e "  ${R}✗ ${#seen[@]} valores DISTINTOS — deben ser idénticos en todos los servicios${N}"
    FAIL=1
  elif [ "${#seen[@]}" -eq 1 ]; then
    echo -e "  ${G}✓ todos coinciden${N}"
  fi
  unset seen
done

# ---------------------------------------------------------------------
# 2. Longitudes y formatos mínimos
# ---------------------------------------------------------------------
echo
echo -e "${B}Formato${N}"

for s in "${SERVICES[@]}"; do
  f="$ROOT/services/$s/.env"

  jwt=$(read_env "$f" JWT_SECRET)
  [ -n "$jwt" ] && [ "${#jwt}" -lt 64 ] && {
    echo -e "  ${R}✗${N} $s: JWT_SECRET tiene ${#jwt} caracteres (mínimo 64)"; FAIL=1; }

  iss=$(read_env "$f" INTER_SERVICE_SECRET)
  [ -n "$iss" ] && [ "${#iss}" -lt 32 ] && {
    echo -e "  ${R}✗${N} $s: INTER_SERVICE_SECRET tiene ${#iss} caracteres (mínimo 32)"; FAIL=1; }

  # Supabase tiene DOS formatos de API key vigentes y ambos son válidos:
  #   · Actual : sb_secret_... / sb_publishable_...  (~40 caracteres)
  #   · Legacy : JWT que empieza por 'eyJ'           (200+ caracteres)
  # Exigir solo el legacy (length > 100) marca como inválida una clave
  # nueva perfectamente correcta.
  srk=$(read_env "$f" SUPABASE_SERVICE_ROLE_KEY)
  if [ -n "$srk" ]; then
    if [[ "$srk" == sb_secret_* || "$srk" == sb_publishable_* ]]; then
      [ "${#srk}" -lt 20 ] && {
        echo -e "  ${R}✗${N} $s: SUPABASE_SERVICE_ROLE_KEY con formato nuevo pero demasiado corta (${#srk})"; FAIL=1; }
    elif [[ "$srk" == eyJ* ]]; then
      [ "${#srk}" -lt 100 ] && {
        echo -e "  ${R}✗${N} $s: SUPABASE_SERVICE_ROLE_KEY legacy demasiado corta (${#srk})"; FAIL=1; }
    else
      echo -e "  ${R}✗${N} $s: SUPABASE_SERVICE_ROLE_KEY con formato desconocido (${#srk} chars)" \
              "— se espera 'sb_secret_...' o un JWT 'eyJ...'"
      FAIL=1
    fi
  fi
done

# ---------------------------------------------------------------------
# 3. Higiene del formato .env
# ---------------------------------------------------------------------
echo
echo -e "${B}Higiene de los .env${N}"
for s in "${SERVICES[@]}"; do
  f="$ROOT/services/$s/.env"
  # Valores con espacios sin entrecomillar: rompen `source` y algunos
  # parsers de .env, y son difíciles de diagnosticar.
  n=$(grep -cE "^[A-Z_]+=[^\"'#]*[[:space:]]+[^\"']" "$f" 2>/dev/null || true)
  [ "${n:-0}" -gt 0 ] && echo -e "  ${Y}!${N} $s: $n valor(es) con espacios sin comillas → entrecomíllalos"
done

# ---------------------------------------------------------------------
echo
if [ "$FAIL" -eq 1 ]; then
  echo -e "${R}Hay secretos incoherentes o inválidos.${N}"
  echo "Para generar y propagar secretos compartidos válidos:"
  echo "  ./scripts/sync-secrets.sh"
  exit 1
fi
echo -e "${G}Secretos coherentes.${N}"
