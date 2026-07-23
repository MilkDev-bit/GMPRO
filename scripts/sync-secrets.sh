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
# Propagar — ATÓMICO (todo-o-nada) con rollback
#
# Antes: sed -i.tmp editaba cada .env en el sitio, uno por uno. Si el 3.º
# fallaba, los servicios 1-2 quedaban con el secreto NUEVO y 3-5 con el
# VIEJO → partición de la malla (401 entre servicios). Además dejaba
# copias .bak.* con los secretos VIEJOS en claro dispersas por el árbol.
#
# Ahora:
#   1. Se preparan TODOS los .env en un stage (copias temporales editadas).
#   2. Solo si los 5 se editaron bien, se mueven de golpe sobre los reales.
#   3. Backups (con secretos viejos) van a un dir temporal con permisos 600
#      y se BORRAN al terminar con éxito; si algo falla, se restauran.
# El secreto nunca se imprime; los ficheros intermedios nunca son legibles
# por otros usuarios.
# ---------------------------------------------------------------------

# Directorio temporal seguro (solo el dueño puede leerlo).
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/gympro-secrets.XXXXXX")"
chmod 700 "$STAGE"
# Limpieza garantizada del stage pase lo que pase (evita secretos en disco).
trap 'rm -rf "$STAGE"' EXIT

# Reemplaza o añade una clave en un archivo, escribiendo a stdout.
# No usa `sed -i`: escribe el resultado por completo, sin ficheros .tmp
# residuales con el secreto.
render_env() {
  local file="$1" ; shift
  # pares clave/valor: k1 v1 k2 v2 ...
  awk -v k1="$1" -v v1="$2" -v k2="$3" -v v2="$4" '
    function setline(line,   key) {
      key = line; sub(/=.*/, "", key); gsub(/^[[:space:]]+/, "", key)
      if (key == k1) { print k1 "=" v1; done1=1; return 1 }
      if (key == k2) { print k2 "=" v2; done2=1; return 1 }
      return 0
    }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=/ { if (setline($0)) next }
    { print }
    END {
      if (!done1) print k1 "=" v1
      if (!done2) print k2 "=" v2
    }
  ' "$file"
}

FILES=()
for d in "$ROOT"/services/*/; do
  f="$d/.env"; [ -f "$f" ] || continue; FILES+=("$f")
done

if [ "$DRY_RUN" = "1" ]; then
  for f in "${FILES[@]}"; do echo "  [dry-run] actualizaría $(basename "$(dirname "$f")")"; done
else
  # ── Fase 1: preparar TODO en el stage ──────────────────────────────
  i=0
  for f in "${FILES[@]}"; do
    staged="$STAGE/staged.$i.env"
    ( umask 077; render_env "$f" JWT_SECRET "$JWT" INTER_SERVICE_SECRET "$ISS" > "$staged" )
    # Verificación por archivo: ambos valores quedaron exactamente escritos.
    if [ "$(read_env "$staged" JWT_SECRET)" != "$JWT" ] || \
       [ "$(read_env "$staged" INTER_SERVICE_SECRET)" != "$ISS" ]; then
      echo -e "  ${Y}✗${N} Falló la preparación de $(basename "$(dirname "$f")"). Abortado, NADA se modificó."
      exit 1
    fi
    i=$((i+1))
  done

  # ── Fase 2: backup seguro + commit atómico ─────────────────────────
  # Backups con secretos VIEJOS al stage (600), no dispersos por el repo.
  i=0
  for f in "${FILES[@]}"; do
    ( umask 077; cp "$f" "$STAGE/backup.$i.env" )
    i=$((i+1))
  done

  i=0
  for f in "${FILES[@]}"; do
    if ! mv "$STAGE/staged.$i.env" "$f"; then
      echo -e "  ${Y}✗${N} Fallo escribiendo $f. Restaurando TODO desde backup…"
      j=0
      for g in "${FILES[@]}"; do cp "$STAGE/backup.$j.env" "$g" 2>/dev/null || true; j=$((j+1)); done
      exit 1
    fi
    echo -e "  ${G}✓${N} $(basename "$(dirname "$f")") actualizado"
    i=$((i+1))
  done

  # ── Fase 3: verificación de consistencia transversal ───────────────
  # Los 5 deben tener EXACTAMENTE el mismo par de secretos, o la malla
  # se particiona. Se comprueba por huella (sin exponer el valor).
  jwt_fp=$(printf '%s' "$JWT" | sha256sum | cut -c1-8)
  iss_fp=$(printf '%s' "$ISS" | sha256sum | cut -c1-8)
  bad=0
  for f in "${FILES[@]}"; do
    a=$(printf '%s' "$(read_env "$f" JWT_SECRET)"          | sha256sum | cut -c1-8)
    b=$(printf '%s' "$(read_env "$f" INTER_SERVICE_SECRET)" | sha256sum | cut -c1-8)
    [ "$a" = "$jwt_fp" ] && [ "$b" = "$iss_fp" ] || { echo -e "  ${Y}✗ inconsistente: $f${N}"; bad=1; }
  done
  [ "$bad" = "0" ] && echo -e "  ${G}✓ los 5 servicios comparten el mismo par de secretos${N}"
fi

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
