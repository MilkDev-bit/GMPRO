# Remediación de seguridad — Consolidado FINAL (revisión CISO)

> Rama de consolidación: `security/consolidado-final` (temporal, **NO main**).
> Fecha: 2026-07-29.

## 0. Estado de la consolidación y de los tests

**Topología encontrada (importante):**
- **Fase 1 y Fase 2 YA están en `origin/main`** — fusionadas por TI vía los PRs de
  GitHub **#8, #9 y #10** (`origin/main` == `f1adf52`, que ya contiene ambas fases).
- **`security/fase-3-estructural` nunca existió como rama**; sus cambios y los de
  **fase-1-móvil (críticos)** estaban **sin commitear** en el working tree.

**Qué hice para consolidar (sin tocar main):**
1. Creé `security/consolidado-final` desde `origin/main` (ya trae fase-1 + fase-2).
2. Commit **fase-1-móvil** → `32ffda0`.
3. Los cambios de **fase-3** quedaron **aplicados en el working tree** (el
   `.git/HEAD.lock` del entorno se re-crea tras cada commit y no se puede eliminar,
   así que B/C no commitearon; el código SÍ está en los archivos y se testeó).

**Conflictos de merge:** **ninguno**. Fase 1 y Fase 2 ya estaban integradas; fase-3 y
fase-1-móvil son cambios **aditivos** que se aplican limpiamente encima.

**Suite de tests completo (estado consolidado):**

| Servicio | Resultado |
|----------|-----------|
| auth-service | **50 passed**, 8 skipped (incl. `rateLimiterFailClosed` ×4, `jwtAsymmetric` ×5) |
| access-service | **8 passed** |
| payment-service | **30 passed**, 3 skipped |
| ai-service | **46 passed** (incl. `safeImageFetch` ×6, `ssrfGuard` ×33) |
| fitness-service | **sin tests** (0 archivos de test en el repo) |
| packages_shared | jest no instalado local (403); sus módulos se cubren **vía los servicios** |

**Total: 134 passed · 0 fallos · 0 conflictos.** `node --check` OK en todo el backend
tocado. *(Los skipped son tests de integración contra Postgres real, gateados por `DATABASE_URL`.)*

---

## 1. Tabla de hallazgos (ID · fase · estado)

Estados: **✅ Corregido y validado** (código + tests/CI) · **🟡 Corregido, pendiente
validación manual** (código listo, falta build/navegador/dispositivo) · **🔶 Pendiente
de decisión o credencial tuya** (o ejecución en consola cloud/store).

| ID (informe) | Fase | Estado | Nota |
|--------------|------|--------|------|
| A02-1 `.dockerignore` raíz | F1 | ✅ Corregido y validado | en `main` |
| A02-2 borrar `.env.bak` | F1 | 🟡 secretos vaciados; falta `rm` de inodos + rotar | manual |
| A03-1 `permissions` en workflows | F1 | ✅ Corregido y validado | en `main` |
| A03-2 pin actions a SHA | F1 | 🔶 4/6 resueltos; faltan 2 + nuevas de F2 | `gh` (script listo) |
| CLD-2 imagen base por digest | F1 | ✅ Corregido y validado | en `main` |
| CLD-5 Redis con auth | F1 | ✅ código; 🔶 falta definir `REDIS_PASSWORD` | decisión/credencial |
| A04-2 eliminar `ENCRYPTION_KEY` | F1 | ✅ Corregido y validado | en `main` |
| API9 rutas legacy deprecadas | F1 | ✅ Corregido y validado | en `main` |
| API3 over-fetching `select('*')` | F1 | 🔶 pendiente confirmar columnas en staging | acceso staging |
| AND-1 firma release Android | F1-móvil | ✅ código (lee CI); 🔶 falta **keystore** | credencial/CI |
| AND-2 / IOS-1 cert pinning | F1-móvil | 🟡 anti-brick + kill-switch; 🔶 faltan **pines SPKI reales** | credencial |
| AND-3 / IOS-2 RASP ids | F1-móvil | ✅ package/bundle; 🔶 faltan `signingCertHashes` + `teamId` | credencial |
| A10-1 rate limiter fail-closed | F2 | ✅ Corregido y validado (4 tests) | en `main` |
| A03-3/4 · CLD-3 SCA/SBOM/imágenes | F2 | 🟡 workflows report-only; falta 1er barrido + gate | en `main` + manual |
| A09-3 / CLD-7 Sentry + alertas | F2 | ✅ código; 🔶 falta `SENTRY_DSN` + reglas de alerta | credencial |
| A08-2 CSP + self-host fuente | F2 | 🟡 código; falta `npm install` + validar navegador | en `main` + manual |
| A04-1 / CLD-4 JWT asimétrico | F3 | ✅ Corregido y validado (5 tests, convivencia) | activación = manual |
| A01-3 SSRF guard cableado | F3 | ✅ Corregido y validado (39 tests) | wire al añadir endpoint |
| CLD-1 roles BD mínimo privilegio | F3 | 🔶 **propuesta SQL `009_*` (no ejecutada)** | Supabase |
| A06-1 threat model | F3 | ✅ documento entregado | revisión del equipo |
| IOS-4 OAuth Universal Links | F3 | 🔶 diseño/snippet (sin compilar) | Flutter + store |

**Backlog aún no abordado** (identificado en auditoría, fuera del alcance de F1–F3):
AND-4 / IOS-3 (Isar sin cifrar con PII), AND-5 (R8/minify Android).

---

## 2. Pendiente **específicamente de ti** (agrupado y priorizado)

### 🔴 P1 — Bloqueantes de release móvil (credenciales/decisiones tuyas)
1. **Keystore de release Android** (AND-1): generar con `keytool`, cargar
   `ANDROID_KEYSTORE_BASE64` + `ANDROID_KEY_PROPERTIES_BASE64` como secretos de CI.
2. **Pines SPKI reales** del dominio de producción (AND-2/IOS-1): leaf + backup
   (comando `openssl` en `remediation-fase1-movil.md`).
3. **`signingCertHashes` (del keystore) + `teamId` de Apple** (AND-3/IOS-2).

### 🟠 P2 — Activaciones de seguridad ya codificadas (variables/consola)
4. **`SENTRY_DSN`** en Railway (5 servicios) + CI, `npm install @sentry/node`, y crear
   las **3 reglas de alerta** (`WEBHOOK_SIGNATURE_INVALID`, `INTER_SERVICE_AUTH_FAILED`,
   ráfaga `LOGIN_FAILED`).
5. **`REDIS_PASSWORD`** definido en el entorno (CLD-5, el compose lo exige).
6. **CORS**: añadir el origin del panel a `CORS_ALLOWED_ORIGINS` (auth, payment).
7. **JWT asimétrico** (A04-1): generar par de claves, distribuir `JWT_PUBLIC_KEY`,
   activar `JWT_PRIVATE_KEY` solo en auth, retirar `JWT_SECRET` tras la ventana.

### 🟡 P3 — Ejecución en consola cloud / staging
8. **Migración 009 (roles BD)** en Supabase: leer los **riesgos** de
   `PR-DESCRIPTION-consolidado.md §3` (interpolación `psql -v`, `CREATE POLICY` no
   idempotente, confirmar RLS deny-all en 15 tablas, `ejercicios` vs
   `catalogo_ejercicios`); **probar en staging primero**; canary por servicio.
9. **API3**: confirmar columnas reales en staging → aplicar `SAFE_COLUMNS`.

### 🟢 P4 — CI / higiene (decisión, sin credencial nueva)
10. Revisar el **primer barrido** de `security-scan.yml` y **activar el gate**.
11. **Pin a SHA** de las 2 actions de F1 + las nuevas de F2 (A03-2).
12. **CSP del panel** (A08-2): `npm install`, `build && preview`, revisar consola;
    fijar CSP también como **cabecera HTTP**.
13. `rm -f services/*/.env.bak.*` y **rotar** secretos potencialmente expuestos.

### 🔵 P5 — Producto / documentación
14. **OAuth iOS** (IOS-4): implementar en Flutter + Associated Domains + **release en
    store** antes de retirar el URL scheme viejo.
15. Revisar y completar el **threat model** (A06-1) con el equipo.
16. Priorizar el **backlog** (Isar cifrado AND-4/IOS-3, R8 AND-5).

---

## 3. Confirmación explícita sobre `main` / `master`

- **Yo (el agente) NO he mergeado ningún cambio a `main`/`master`.** Toda mi salida en
  esta sesión vive en ramas `security/*` y en el working tree.
- **Sí existen cambios de seguridad ya en `origin/main`**, pero fueron fusionados
  **por TI** mediante los **PRs #8, #9 y #10** de GitHub (Fase 1 y Fase 2). Eso
  constituye tu aprobación explícita de esas dos fases.
- **Fase 3 y fase-1-móvil NO están en `main`**: viven en `security/consolidado-final`
  (fase-1-móvil commiteada en `32ffda0`; fase-3 aplicada en working tree, pendiente de
  commit por el bloqueo de `HEAD.lock` del entorno — comandos abajo).
- La rama de consolidación **no se pusheó ni se mergeó**; queda para tu revisión.

**Para cerrar los commits pendientes (en tu máquina):**
```bash
git checkout security/consolidado-final
rm -f .git/index.lock .git/HEAD.lock 2>/dev/null
git add packages_shared/security/jwtVerify.js \
        services/auth-service/src/config/environment.js \
        services/auth-service/src/services/tokenService.js \
        services/auth-service/tests/jwtAsymmetric.test.js \
        services/ai-service/src/services/safeImageFetch.js \
        services/ai-service/tests/safeImageFetch.test.js \
        docs/database/schemas/migrations/009_least_privilege_roles.sql \
        docs/security/threat-model.md docs/security/remediation-fase3-estructural.md
git commit -m "feat(sec): Fase 3 estructural (JWT asimetrico, SSRF guard, roles BD propuesta, threat model, OAuth iOS)"
git add docs/security/CHANGELOG-remediacion.md docs/security/PR-DESCRIPTION-consolidado.md \
        docs/security/remediation-final-consolidado.md
git commit -m "docs(sec): consolidacion final + changelog + PR description"
```
> Nota: quedan cambios **ajenos a seguridad** sin commitear (módulo de ofertas,
> dashboard, migración 008, `package*.json` de la raíz). No los incluí en las ramas
> de seguridad; gestiónalos aparte.

---

## 4. Orden recomendado de revisión y aprobación

Ordenado de menor a mayor riesgo. Fase 3 (BD + JWT) **se revisa aparte**.

1. **Fase 1 (`security/fase-1-infra-cicd`)** — *ya en main (PRs #8/#9)*. Riesgo bajo:
   config/CI/infra. Verificar en retrospectiva que el gate de CI y CORS quedaron OK.
2. **Fase 2 (`security/fase-2-mediano`)** — *ya en main (PR #10)*. Riesgo medio.
   **Acción post-merge:** validar el fail-closed del rate limiter y la CSP en un
   entorno real; cargar `SENTRY_DSN`; revisar el 1er barrido de escaneo.
3. **Fase 1-móvil (`security/consolidado-final`, commit `32ffda0`)** — riesgo medio,
   **bloqueante de release**. Revisar el anti-brick del pinning y que la firma lea del
   CI. **No publicar** hasta rellenar pines/keystore/RASP.
4. **Fase 3 — Sub-PR A (código):** JWT asimétrico + SSRF + threat model. Es
   **retrocompatible** (sin `JWT_PRIVATE_KEY` firma HS*) y está **cubierto por tests**
   → apto para merge con **revisión de seguridad dedicada**. Activación (claves) por
   variables de entorno, reversible.
5. **Fase 3 — Sub-PR B (NO ejecutable por merge):** migración `009_*.sql` y snippet
   iOS. **No mergear como algo que se “activa”**; son entregables para **ejecución
   manual** (Supabase en staging→prod, release en store) tras aplicar los riesgos §3.

**Regla transversal:** el merge del código es seguro porque **ningún control se activa
solo por mergear** — la activación (firma asimétrica, roles de BD, gate de CI,
pinning/RASP) se hace por variable de entorno o ejecución manual, controlada y reversible.
