-- =============================================================================
-- 013 · CANÓNICO access_service_db — tablas alineadas al CÓDIGO
-- Fecha: 2026-07-29 · Ver docs/database/SCHEMA-DIVERGENCE-REPORT.md
-- =============================================================================
-- El DDL de 01 para historial_accesos y tickets_visitas es un diseño DISTINTO al
-- que el código realmente usa (accessModel.js). Como la BD está vacía, se
-- RECREAN alineadas al código. Al hacer DROP se pierden RLS/grants/policies, así
-- que se re-crean aquí (mínimo privilegio: svc_access RW; svc_payment SELECT en
-- historial_accesos por el fallback del torniquete).
-- Idempotente-ish: DROP ... IF EXISTS + CREATE. Seguro de re-ejecutar en BD vacía.
-- =============================================================================

BEGIN;

-- Orden: primero las dependientes, luego historial_accesos.
DROP TABLE IF EXISTS access_service_db.tickets_visitas       CASCADE;
DROP TABLE IF EXISTS access_service_db.qr_nonces_consumidos  CASCADE;
DROP TABLE IF EXISTS access_service_db.historial_accesos     CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- historial_accesos — log de ingresos (accessModel.recordAccess)
--   insert: usuario_id, fecha_hora, acceso_concedido, razon_rechazo, metodo_acceso, token_codigo
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE access_service_db.historial_accesos (
  id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id       UUID        NOT NULL,
  fecha_hora       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acceso_concedido BOOLEAN     NOT NULL DEFAULT true,
  razon_rechazo    TEXT,
  metodo_acceso    TEXT        NOT NULL DEFAULT 'qr' CHECK (metodo_acceso IN ('qr','ticket','manual')),
  token_codigo     TEXT
);
CREATE INDEX idx_ha_usuario_fecha ON access_service_db.historial_accesos(usuario_id, fecha_hora DESC);
CREATE INDEX idx_ha_token_codigo  ON access_service_db.historial_accesos(token_codigo);

-- ─────────────────────────────────────────────────────────────────────────────
-- tickets_visitas — pases de un solo uso (accessModel: createTicketRecord/consume)
--   codigo_ticket UNIQUE; estado 'active'|'used' (+ 'valido' legacy); usado_at/usado_en
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE access_service_db.tickets_visitas (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id    UUID,
  codigo_ticket TEXT        NOT NULL UNIQUE,
  estado        TEXT        NOT NULL DEFAULT 'active' CHECK (estado IN ('active','used','valido','usado')),
  expira_en     TIMESTAMPTZ NOT NULL,
  notas         TEXT,
  usado_at      TIMESTAMPTZ,
  usado_en      TIMESTAMPTZ,                        -- alias por compatibilidad (el código escribe ambos)
  creado_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_tv_codigo ON access_service_db.tickets_visitas(codigo_ticket);

-- ─────────────────────────────────────────────────────────────────────────────
-- qr_nonces_consumidos — anti-replay de QR (accessModel.claimQrNonceAtomically)
--   PK = nonce (23505 = replay). insert: nonce, usuario_id, turnstile_id
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE access_service_db.qr_nonces_consumidos (
  nonce        TEXT        PRIMARY KEY,
  usuario_id   UUID        NOT NULL,
  turnstile_id TEXT,
  consumido_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── RLS deny-all + mínimo privilegio (recrea lo que el DROP se llevó) ─────────
ALTER TABLE access_service_db.historial_accesos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_service_db.tickets_visitas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_service_db.qr_nonces_consumidos  ENABLE ROW LEVEL SECURITY;

CREATE POLICY deny_all_access_historial ON access_service_db.historial_accesos   FOR ALL TO public USING (false);
CREATE POLICY deny_all_access_tickets   ON access_service_db.tickets_visitas      FOR ALL TO public USING (false);
CREATE POLICY deny_all_qr_nonces        ON access_service_db.qr_nonces_consumidos FOR ALL TO public USING (false);

-- svc_access: RW sobre sus 3 tablas
GRANT SELECT, INSERT, UPDATE ON
  access_service_db.historial_accesos,
  access_service_db.tickets_visitas,
  access_service_db.qr_nonces_consumidos
  TO svc_access;
CREATE POLICY svc_access_rw ON access_service_db.historial_accesos    FOR ALL TO svc_access USING (true) WITH CHECK (true);
CREATE POLICY svc_access_rw ON access_service_db.tickets_visitas       FOR ALL TO svc_access USING (true) WITH CHECK (true);
CREATE POLICY svc_access_rw ON access_service_db.qr_nonces_consumidos  FOR ALL TO svc_access USING (true) WITH CHECK (true);

-- svc_payment: SELECT en historial_accesos (fallback del torniquete, worker de retención)
GRANT SELECT ON access_service_db.historial_accesos TO svc_payment;
CREATE POLICY svc_payment_ro_h ON access_service_db.historial_accesos FOR SELECT TO svc_payment USING (true);

COMMIT;
