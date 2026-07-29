# PR — Remediación de seguridad (Fases 1, 2 y 3)

> Consolidado de las ramas `security/fase-1-infra-cicd`, `security/fase-2-mediano`
> y `security/fase-3-estructural`. Basado en `audit-final-consolidado.md` y los
> informes `remediation-fase1-*.md`, `remediation-fase2.md`,
> `remediation-fase3-estructural.md`. **No mergear todo junto** — ver §5.

---

## 1. Resumen ejecutivo

Este trabajo cierra los hallazgos priorizados de la auditoría OWASP (web/API,
Android, iOS, cloud). **Corregido en código y validado con tests/CI:** rate limiter
**fail-closed** (Fase 2, 4 tests), **JWT asimétrico con convivencia** RS256/HS*
(Fase 3, 5 tests), **SSRF guard cableado** en `fetchUserImage` (Fase 3, 39 tests),
`.dockerignore` raíz, `permissions` mínimos + imagen base por digest en CI,
Redis con auth en compose, `ENCRYPTION_KEY` muerta eliminada, deprecación no
destructiva de rutas legacy (API9), integración de **Sentry** (env-based) y **CSP +
self-host de fuente** en el panel. La regresión de auth queda **intacta (50 passed)**.

**Diseño/propuesta sin ejecutar:** migración de **roles de BD de mínimo privilegio**
(`009_*.sql`, retiro de `service_role`), **threat model** (DFD+STRIDE) y el flujo
**OAuth iOS por Universal Links** (snippet sin compilar por falta de toolchain iOS).

**Depende de acceso/decisiones fuera del repo:** aplicar la migración 009 en
Supabase, cargar `SENTRY_DSN`, generar el keystore de release Android, configurar
Associated Domains en App Store Connect, y confirmaciones de esquema (§3).

---

## 2. Checklist de ejecución manual (por sistema)

### Supabase
- [ ] Aplicar `docs/database/schemas/migrations/009_least_privilege_roles.sql`
      (roles `svc_*` de mínimo privilegio) **leyendo antes los riesgos de la §3**.
- [ ] Migrar cada servicio de `service_role` al rol nuevo (canary, orden
      `ai → fitness → access → auth → payment`) y, tras estabilizar, **rotar
      `service_role`**.
- [ ] Confirmar que las 15 tablas tienen **RLS deny-all** habilitado (§3).
- [ ] Aplicar migraciones pendientes previas si no lo están: `007_ofertas.sql`,
      `008_historial_pagos_online.sql`.

### Sentry
- [ ] Cargar el **DSN** del proyecto Node.js como `SENTRY_DSN` (variable de entorno)
      en **Railway** (los 5 servicios) y en **CI** donde aplique.
- [ ] `npm install` en `packages_shared` (ya se añadió `@sentry/node` al `package.json`).
- [ ] Crear las **3 reglas de alerta**: `WEBHOOK_SIGNATURE_INVALID`,
      `INTER_SERVICE_AUTH_FAILED`, ráfaga de `LOGIN_FAILED` (umbral por frecuencia).

### Android
- [ ] **Generar el keystore de release** (`keytool`) fuera del repo y guardarlo seguro.
- [ ] Cargarlo como secretos de CI: `ANDROID_KEYSTORE_BASE64` y
      `ANDROID_KEY_PROPERTIES_BASE64` (el `build.gradle.kts` ya los consume vía
      `android/key.properties`).
- [ ] Obtener el **SHA-256 (base64) del cert de release** y ponerlo en el
      `signingCertHashes` de RASP (`security_guard.dart`, hoy pendiente).

### iOS / App Store Connect
- [ ] Configurar **Universal Links / Associated Domains** (`applinks:<dominio>` +
      `apple-app-site-association`) para el nuevo flujo OAuth (IOS-4).
- [ ] Rellenar los pendientes móviles de Fase 1: **pines SPKI reales**
      (`certificatePins`), **`teamId`** de Apple y `bundleIds`/`packageName` de RASP
      (bundle ya confirmado `com.gympro.mobile`).
- [ ] Publicar una **nueva versión** en la store antes de retirar el URL scheme viejo.

### Otros pendientes de Fases 1 y 2 (sin credenciales/confirmación)
- [ ] **Redis auth (CLD-5):** definir `REDIS_PASSWORD` en el entorno antes de
      `docker compose up` (el compose lo exige con `:?`).
- [ ] **CORS:** añadir el origin del panel a `CORS_ALLOWED_ORIGINS` de auth y payment.
- [ ] **SCA/SBOM/imágenes (A03-3/4, CLD-3):** revisar el **primer barrido** de
      `security-scan.yml` (report-only) y **activar el gate** (quitar
      `continue-on-error` / `exit-code: "1"`) tras revisar el backlog inicial.
- [ ] **A03-2:** pinnear a **SHA** las 2 actions de Fase 1 sin resolver
      (`subosito/flutter-action@v2`, `ruby/setup-ruby@v1`) y las nuevas de
      `security-scan.yml` (marcadas con `# TODO A03-2`).
- [ ] **JWT asimétrico (rotación):** generar el par de claves, distribuir la
      **pública** (`JWT_PUBLIC_KEY`) a los 5 servicios, activar `JWT_PRIVATE_KEY`
      solo en auth, y **retirar `JWT_SECRET`** tras la ventana de expiración.
- [ ] **CSP del panel (A08-2):** `npm install` (`@fontsource/inter`), `npm run build
      && preview` y revisar la **consola del navegador**; fijar la CSP también como
      **cabecera HTTP** en el host.
- [ ] **API3 (over-fetching):** confirmar columnas reales en staging y sustituir
      `select('*')` por `SAFE_COLUMNS` (plantilla en `remediation-fase1-api.md`).
- [ ] **`.env.bak`:** `rm -f services/*/.env.bak.*` (ya vaciados de secretos) y
      **rotar** cualquier secreto que hayan contenido.

---

## 3. ⚠ Riesgos en `009_least_privilege_roles.sql` (leer ANTES de ejecutar)

Documentados aquí para que **no se pierdan** antes de correr la migración:

1. **`PASSWORD :'VARIABLE'` no es SQL estándar.** Es interpolación de variables de
   `psql -v` (`psql -v AUTH_DB_PASSWORD=... -f 009_*.sql`). **No se puede pegar tal
   cual en el SQL Editor de Supabase.** Ejecutar por `psql` con las variables reales,
   o **reemplazar cada placeholder por su valor justo antes de correr** el script —
   **nunca versionar las contraseñas en claro**.
2. **`CREATE POLICY` no es idempotente.** Si el script se re-ejecuta tras un fallo
   parcial, **tronará por política duplicada**. Antes de ejecutar: anteponer
   `DROP POLICY IF EXISTS <nombre> ON <tabla>;` a cada `CREATE POLICY`, o envolver en
   un bloque `DO $$ … EXCEPTION WHEN duplicate_object THEN NULL; END $$;`.
3. **Confirmar RLS deny-all en las 15 tablas.** El diseño asume que cada tabla tiene
   `ALTER TABLE … ENABLE ROW LEVEL SECURITY` + policy `FOR ALL TO public USING (false)`.
   Si **alguna no lo tiene**, el rol nuevo (que suma su policy `TO svc_*`) quedaría
   con **acceso más amplio del esperado** (sin la barrera deny-all). Verificar tabla
   por tabla antes de aplicar.
4. **Nombre real de la tabla de ejercicios.** Confirmar contra
   `information_schema.tables` si es **`ejercicios`** o **`catalogo_ejercicios`**
   (los modelos consultan `ejercicios`, pero los docs de esquema definen
   `catalogo_ejercicios`) antes de ejecutar el `GRANT`/`CREATE POLICY` de fitness.
   Aplica también a otros nombres que puedan diferir del schema documentado.
5. **Probar en staging primero.** Correr la migración completa en un
   **branch/proyecto de staging de Supabase** y validar que cada servicio funciona
   con su rol nuevo **antes de tocar producción**.

> Verificación rápida de RLS por tabla:
> ```sql
> SELECT n.nspname AS schema, c.relname AS tabla, c.relrowsecurity AS rls
> FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
> WHERE c.relkind='r' AND n.nspname LIKE '%_service_db' ORDER BY 1,2;  -- rls debe ser 't'
> ```

---

## 4. Validado con tests vs diseño sin compilar

**Validado con tests automatizados (jest):**
- **Ítem 2 — JWT asimétrico:** 5 tests (acepta RS256 nuevo, sigue aceptando HS512
  viejo, rechaza confusión RS/HS, expirado y `alg:none`).
- **Ítem 4 — SSRF `fetchUserImage`:** 39 tests (rechaza loopback/RFC1918/metadata/
  IPv6/http/credenciales y **no** llama a fetch; permite externa https válida).
- **Fase 2 — rate limiter fail-closed:** 4 tests (503 en prod sin Redis, `/health`
  vivo, MemoryStore en dev, error de store → bloqueado).
- **Regresión de auth intacta: 50 passed** (más 30 en payment, 8 en access).

**Diseño / manual, sin ejecutar:**
- **Ítem 1 — migración SQL de roles:** propuesta `009_*.sql`, **con los riesgos de la
  §3** (no ejecutada; requiere `psql`/staging + confirmaciones de esquema).
- **Ítem 3 — threat model:** `docs/security/threat-model.md`, documento de revisión
  (DFD+STRIDE); sin código.
- **Ítem 5 — OAuth iOS:** snippet de `ASWebAuthenticationSession`/Universal Links
  **sin compilar** (falta toolchain iOS); requiere implementación + release en store.

> Limitación del entorno: sin toolchain de Flutter/Gradle/navegador ni acceso a
> Supabase/stores; las validaciones fuera de jest quedan como *pendiente manual*.

---

## 5. Orden recomendado de revisión y merge

**No mergear las tres fases en un solo PR.** Revisar y mergear por separado, de menor
a mayor riesgo:

1. **Fase 1 (`security/fase-1-infra-cicd`) — bajo riesgo, primero.**
   Config/CI/infra (`.dockerignore`, `permissions`, digest, Redis auth, API9,
   `ENCRYPTION_KEY`). Ya en `origin`. Revisión estándar → merge.
2. **Fase 2 (`security/fase-2-mediano`) — riesgo medio.**
   Rate limiter fail-closed (con tests), Sentry (no-op sin DSN), CSP + fuente,
   SCA/SBOM/imágenes en **report-only** (no bloquea). Revisar que el fail-closed y la
   CSP no afecten disponibilidad; merge tras validar Sentry/CSP en un entorno real.
3. **Fase 3 (`security/fase-3-estructural`) — MAYOR riesgo, revisión SEPARADA.**
   Contiene los cambios sensibles: **JWT asimétrico** (afecta autenticación de todo
   el sistema) y la **propuesta de roles de BD** (afecta acceso a datos). Recomendado:
   - **Sub-PR A (código, mergeable):** JWT convivencia + SSRF `fetchUserImage` +
     threat model. Es retrocompatible (sin `JWT_PRIVATE_KEY` sigue firmando HS*) y
     está cubierto por tests → puede mergear con revisión de seguridad dedicada.
   - **Sub-PR B (NO mergear a main como ejecutable):** la migración `009_*.sql` y el
     snippet iOS quedan como **entregables para ejecución manual** (Supabase/store),
     tras aplicar la §3 y probar en staging. No se activan con un merge.

**Regla transversal:** la activación real de cada control (firma asimétrica, roles de
BD, gate de CI, pinning/RASP móvil) se hace por **variables de entorno/ejecución
manual**, no por el merge — de modo que mergear el código es seguro y la activación
es un paso controlado y reversible.
