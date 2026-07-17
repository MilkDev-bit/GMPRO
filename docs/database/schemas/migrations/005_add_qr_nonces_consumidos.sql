-- =============================================================================
-- MIGRACIÓN 005: qr_nonces_consumidos — anti-replay DURABLE para QR dinámicos
-- =============================================================================
-- Versión      : 005
-- Fecha        : 2026-07-17
-- Autor        : GymPro Security
-- Descripción  : Corrige la vulnerabilidad de RACE CONDITION / replay del flujo QR
--               (qrController.verifyQr). El control anterior consultaba
--               isNonceAlreadyUsed() y luego registraba el acceso en dos pasos NO
--               atómicos: dos escaneos simultáneos del MISMO QR (captura de pantalla
--               revendida) pasaban ambos la verificación y abrían el torniquete dos
--               veces dentro de la ventana de 30 s.
--
--               Esta tabla da una garantía atómica a nivel DB: el nonce es PRIMARY
--               KEY, por lo que el PRIMER INSERT gana y cualquier INSERT concurrente
--               del mismo nonce falla con violación de unicidad (código 23505). Es
--               independiente de Redis (fail-closed aunque la caché esté caída).
--
-- EJECUCIÓN: aplicar en Supabase SQL Editor una sola vez.
-- =============================================================================

CREATE TABLE IF NOT EXISTS access_service_db.qr_nonces_consumidos (
  nonce          VARCHAR(64)  PRIMARY KEY,          -- 128-bit hex del QR (un solo uso)
  usuario_id     UUID         NOT NULL,
  consumido_en   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  turnstile_id   VARCHAR(80)                        -- lectora que lo consumió (auditoría)
);

-- Barrido de expirados: los nonces solo importan durante su TTL (30 s) + holgura.
-- Un job/cron puede purgar filas viejas para mantener la tabla pequeña.
CREATE INDEX IF NOT EXISTS idx_qr_nonces_consumido_en
  ON access_service_db.qr_nonces_consumidos (consumido_en);

-- RLS: solo el service_role (access-service) accede. Bloqueo total al público.
ALTER TABLE access_service_db.qr_nonces_consumidos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS deny_all_qr_nonces ON access_service_db.qr_nonces_consumidos;
CREATE POLICY deny_all_qr_nonces
  ON access_service_db.qr_nonces_consumidos FOR ALL
  USING (false) WITH CHECK (false);

COMMENT ON TABLE access_service_db.qr_nonces_consumidos IS
  'Registro atómico de nonces de QR ya consumidos. PK = garantía anti-replay a nivel DB. Tarea 3.2 (fix de concurrencia).';
