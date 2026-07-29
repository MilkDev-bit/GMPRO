# Threat Model — GymPro (documento inicial, A06-1)

> Punto de partida para que el equipo revise y complete. Método: DFD (flujo de
> datos) + **STRIDE** por flujo crítico, mapeando cada amenaza a los controles YA
> existentes y a los huecos. Fecha: 2026-07-24. Alcance: flujos de **pago**,
> **acceso físico**, **identidad** e **IA/PII**.

## 0. Vista de sistema y límites de confianza (trust boundaries)

```
[App móvil Flutter]         [Panel web React]        [Hardware recepción (IoT)]
        │  TLS (pinning)            │  TLS                    │  API Key / serial
        ▼                           ▼                         ▼
════════════════════ LÍMITE DE CONFIANZA: INTERNET / edge Railway ════════════════
        ▼                           ▼                         ▼
┌──────────────────────────── Microservicios (Express) ───────────────────────────┐
│ auth · access · payment · fitness · ai      (JWT, RBAC, rate limit, helmet)      │
└───────────────┬───────────────────────┬─────────────────────────────┬───────────┘
   M2M (secret) │        service_role    │ (webhooks firmados)         │
════════════════▼════════════ LÍMITE DE CONFIANZA: red interna ═══════════════════
        ┌───────────────┐        ┌──────────┐              ┌─────────────────┐
        │ Supabase/PG   │        │  Redis   │              │ Stripe / LLM API │
        │ (RLS deny-all)│        │ (cache)  │              │  (terceros)      │
        └───────────────┘        └──────────┘              └─────────────────┘
```

Límites clave: (1) cliente↔API (internet), (2) API↔datos (red interna),
(3) API↔terceros (Stripe/LLM), (4) hardware↔API (recepción). Activos sensibles:
credenciales/JWT, PII de socios, datos de pago, control de acceso físico.

---

## 1. Flujo: PAGO (checkout Stripe + webhook + cobro presencial)

**DFD:** App → `payment/create-checkout-session` → Stripe → (usuario paga) →
Stripe **webhook** `payment/webhooks/stripe` → activa suscripción + asienta en
`historial_pagos`. Recepción → `cash-payment` (API Key) → `registrar_pago_efectivo`.

| STRIDE | Amenaza | Control existente | Hueco / acción |
|--------|---------|-------------------|----------------|
| **S**poofing | Webhook falso "pago exitoso" | Verificación de firma HMAC Stripe (`constructEvent`) | — |
| **T**ampering | Alterar monto/estado en tránsito | TLS; body raw firmado | — |
| **R**epudiation | Doble procesamiento / negar cobro | Idempotencia atómica (PK `webhook_events_procesados`); ledger inmutable | Alerta en `WEBHOOK_SIGNATURE_INVALID` (Fase 2) |
| **I**nfo disclosure | Fuga de PAN/PII | Stripe tokeniza; recibos con ownership check | select('*') en `historial_pagos` → columnas explícitas (API3) |
| **D**oS | Abuso del endpoint de pago | Rate limit 10/min | Rate limiter fail-closed (Fase 2) |
| **E**oP | Cupón abusado / IDOR de suscripción | Canje atómico + tope; RBAC admin | — |

## 2. Flujo: ACCESO FÍSICO (QR dinámico + torniquete)

**DFD:** App → `access/generate-qr` (JWT) → QR cifrado AES-256-GCM →
Torniquete escanea → `access/validate-ticket|validate-qr` (API Key) → nonce de un
solo uso + mutex Redis → abre relé.

| STRIDE | Amenaza | Control existente | Hueco / acción |
|--------|---------|-------------------|----------------|
| **S**poofing | QR falsificado | AES-256-GCM autenticado (authTag) | — |
| **T**ampering | Reusar/replicar QR | Nonce single-use (Redis + BD) + timestamp | — |
| **R**epudiation | Doble apertura concurrente | Mutex distribuido `SET NX PX` + UPDATE condicional | — |
| **I**nfo disclosure | Extraer `usuario_id` del QR | Payload cifrado; solo backend descifra | — |
| **D**oS | Flood de validaciones | Rate limiter del torniquete | fail-closed (Fase 2) |
| **E**oP | Hardware comprometido usa API Key para otros fines | API Key dedicada del torniquete | Rol de BD mínimo (CLD-1) limita el blast radius |

## 3. Flujo: IDENTIDAD (registro/login/refresh/WebAuthn)

**DFD:** App → `auth/login` → JWT (access) + refresh (cookie httpOnly) →
`auth/refresh` rota familia. WebAuthn: challenge server-side single-use.

| STRIDE | Amenaza | Control existente | Hueco / acción |
|--------|---------|-------------------|----------------|
| **S**poofing | Fuerza bruta / credential stuffing | Rate limit IP + por cuenta + lockout; `LOGIN_FAILED`→alerta (Fase 2) | — |
| **T**ampering | Falsificar/alterar JWT (alg:none, RS/HS confusión) | Whitelist de algoritmo; **firma asimétrica** en migración (A04-1) | Completar rotación a RS256 |
| **R**epudiation | Robo de refresh token | Reuse-detection + revocación de familia | — |
| **I**nfo disclosure | Enumeración de cuentas | Mensajes genéricos (login + forgot) | — |
| **D**oS | Agotar login | Rate limiter fail-closed (Fase 2) | — |
| **E**oP | Secreto JWT compartido → forjar tokens de todos | **A04-1**: migración a asimétrico (auth firma, resto verifica pública) | Segregar/rotar secretos (CLD-4) |

## 4. Flujo: IA / PII (chat, nutrición, RAG)

**DFD:** App → `ai/chat` (JWT) → LLM API (externo) + `historial_chat` +
memoria vectorial. Reconciliación de alimentos → Open Food Facts (externo).

| STRIDE | Amenaza | Control existente | Hueco / acción |
|--------|---------|-------------------|----------------|
| **S**poofing | Suplantar usuario en el chat | JWT verificado | — |
| **T**ampering | Inyección de prompt | Validación de esquema; system prompt aislado | Revisar aislamiento de datos personales en caché semántico |
| **R**epudiation | — | Logging estructurado | — |
| **I**nfo disclosure | **SSRF** vía URL de imagen de usuario | `ssrfGuard` **cableado** en `fetchUserImage` (A01-3) | Wire obligatorio al añadir el endpoint multimodal |
| **D**oS | Abuso de tokens LLM (coste) | Rate limiter de IA + timeouts | — |
| **E**oP | Filtrar PII de otros usuarios en respuestas | Aislamiento por `usuario_id`; caché con política de no-personalización | Auditar reglas de cacheabilidad |

---

## 5. Supuestos y decisiones de seguridad (a validar por el equipo)
- El edge de Railway termina TLS y añade 1 hop de proxy (`trust proxy: 1`).
- Supabase RLS está **habilitado por tabla** (deny-all) — **confirmar en consola**.
- `service_role` God-mode compartida → en retiro (CLD-1, migración 009).
- Secreto JWT simétrico compartido → en retiro (A04-1, firma asimétrica).

## 6. Próximos pasos
- Completar STRIDE de flujos secundarios (emails, sincronización biométrica ZKTeco,
  Live Activities).
- Diagramar DFDs formales (herramienta: OWASP Threat Dragon / draw.io).
- Integrar la revisión de este modelo al checklist de PR para features que toquen
  estos flujos.
