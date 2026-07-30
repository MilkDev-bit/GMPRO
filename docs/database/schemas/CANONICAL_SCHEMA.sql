--
-- PostgreSQL database dump
--

\restrict 1qck7LEPlDCx8fLWUafu61nN06d5MvvYYjnH3zdVrYSuFFj0wC3Mp5ajBE1XGtx

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: access_service_db; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA access_service_db;


--
-- Name: SCHEMA access_service_db; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA access_service_db IS 'Dominio de control de acceso físico. Solo accesible por access-service y scripts_local.';


--
-- Name: auth_service_db; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auth_service_db;


--
-- Name: SCHEMA auth_service_db; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA auth_service_db IS 'Dominio de autenticación e identidad. Solo accesible por auth-service.';


--
-- Name: fitness_service_db; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA fitness_service_db;


--
-- Name: SCHEMA fitness_service_db; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA fitness_service_db IS 'Dominio de catálogos de fitness y nutrición. Gestionado por fitness-service. Poblado automáticamente por scripts de seeding desde wger y Open Food Facts.';


--
-- Name: payment_service_db; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA payment_service_db;


--
-- Name: SCHEMA payment_service_db; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA payment_service_db IS 'Dominio de pagos y suscripciones. Solo accesible por payment-service.';


--
-- Name: nivel_ejercicio_enum; Type: TYPE; Schema: fitness_service_db; Owner: -
--

CREATE TYPE fitness_service_db.nivel_ejercicio_enum AS ENUM (
    'principiante',
    'intermedio',
    'avanzado'
);


--
-- Name: region_corporal_enum; Type: TYPE; Schema: fitness_service_db; Owner: -
--

CREATE TYPE fitness_service_db.region_corporal_enum AS ENUM (
    'anterior',
    'posterior'
);


--
-- Name: deny_modification(); Type: FUNCTION; Schema: access_service_db; Owner: -
--

CREATE FUNCTION access_service_db.deny_modification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION
    'La tabla historial_accesos es inmutable. No se permiten UPDATE ni DELETE. [AUDIT-001]';
END;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: access_service_db; Owner: -
--

CREATE FUNCTION access_service_db.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: assign_pin_terminal(uuid); Type: FUNCTION; Schema: auth_service_db; Owner: -
--

CREATE FUNCTION auth_service_db.assign_pin_terminal(p_usuario_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_pin INTEGER;
BEGIN
  -- Si ya tiene PIN, retornarlo directamente
  SELECT pin_terminal INTO v_pin
  FROM auth_service_db.usuarios
  WHERE id = p_usuario_id AND eliminado_en IS NULL;

  IF v_pin IS NOT NULL THEN
    RETURN v_pin;
  END IF;

  -- Generar un nuevo PIN único de la secuencia
  v_pin := nextval('auth_service_db.pin_terminal_seq');

  UPDATE auth_service_db.usuarios
  SET pin_terminal = v_pin, actualizado_en = NOW()
  WHERE id = p_usuario_id AND eliminado_en IS NULL;

  RETURN v_pin;
END;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: auth_service_db; Owner: -
--

CREATE FUNCTION auth_service_db.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: fitness_service_db; Owner: -
--

CREATE FUNCTION fitness_service_db.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$;


--
-- Name: deny_ledger_mutation(); Type: FUNCTION; Schema: payment_service_db; Owner: -
--

CREATE FUNCTION payment_service_db.deny_ledger_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'historial_pagos es inmutable: usa un asiento inverso. [AUDIT-004]';
END;
$$;


--
-- Name: increment_offer_usage(text); Type: FUNCTION; Schema: payment_service_db; Owner: -
--

CREATE FUNCTION payment_service_db.increment_offer_usage(p_codigo text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'payment_service_db'
    AS $$
DECLARE
  nuevos INTEGER;
BEGIN
  UPDATE payment_service_db.ofertas
     SET usos = usos + 1, actualizado_en = NOW()
   WHERE LOWER(codigo) = LOWER(p_codigo)
  RETURNING usos INTO nuevos;
  RETURN nuevos; -- NULL si el código no existe
END;
$$;


--
-- Name: registrar_pago_efectivo(uuid, uuid, numeric, text, text, text, text, text, text); Type: FUNCTION; Schema: payment_service_db; Owner: -
--

CREATE FUNCTION payment_service_db.registrar_pago_efectivo(p_usuario_id uuid, p_plan_id uuid, p_monto_cobrado numeric, p_metodo_pago text, p_receptionist_id text, p_idempotency_key text, p_numero_recibo text, p_pase_cortesia_codigo text DEFAULT NULL::text, p_notas text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'payment_service_db', 'public'
    AS $$
DECLARE
  v_plan            RECORD;
  v_existing_pago   RECORD;
  v_sub             RECORD;
  v_accion          TEXT;
  v_ahora           TIMESTAMPTZ := NOW();
  v_hoy             DATE := (v_ahora AT TIME ZONE 'America/Mexico_City')::date;
  v_valido_hasta    DATE;
  v_variacion       NUMERIC(10,2);
  v_pago            RECORD;
BEGIN
  -- 0. Idempotencia secuencial: ¿ya existe un asiento con esta clave?
  SELECT * INTO v_existing_pago
  FROM historial_pagos
  WHERE idempotency_key = p_idempotency_key;

  IF FOUND THEN
    SELECT * INTO v_sub FROM suscripciones WHERE id = v_existing_pago.suscripcion_id;
    RETURN jsonb_build_object(
      'ya_procesado', true, 'accion', 'idempotent',
      'suscripcion', to_jsonb(v_sub), 'pago', to_jsonb(v_existing_pago)
    );
  END IF;

  -- 1. Plan canónico: la duración es ESTRICTA y sale de aquí.
  SELECT plan_id, nombre, duracion_dias, precio_base_actual, moneda
  INTO v_plan
  FROM planes
  WHERE plan_id = p_plan_id AND activo = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PLAN_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  v_variacion := ROUND(p_monto_cobrado - v_plan.precio_base_actual, 2);

  -- 2. Extender (si hay activa) o crear suscripción — átomico con lo demás.
  SELECT * INTO v_sub
  FROM suscripciones
  WHERE usuario_id = p_usuario_id AND estado = 'active'
  ORDER BY valido_hasta DESC
  LIMIT 1;

  IF FOUND THEN
    v_valido_hasta := GREATEST(v_sub.valido_hasta, v_hoy) + v_plan.duracion_dias;
    UPDATE suscripciones SET
      plan_nombre = v_plan.nombre,
      plan_duracion_dias = v_plan.duracion_dias,
      monto = p_monto_cobrado,
      metodo_pago = p_metodo_pago,
      estado = 'active',
      valido_hasta = v_valido_hasta,
      ultimo_pago_en = v_ahora,
      receptionist_id = p_receptionist_id,
      notas_internas = p_notas,
      cancelado_en = NULL,
      acceso_facial_revocado_en = NULL,
      actualizado_en = v_ahora
    WHERE id = v_sub.id
    RETURNING * INTO v_sub;
    v_accion := 'renewed';
  ELSE
    v_valido_hasta := v_hoy + v_plan.duracion_dias;
    INSERT INTO suscripciones (
      usuario_id, plan_nombre, plan_duracion_dias, monto, moneda,
      metodo_pago, estado, valido_desde, valido_hasta, ultimo_pago_en,
      receptionist_id, notas_internas
    ) VALUES (
      p_usuario_id, v_plan.nombre, v_plan.duracion_dias, p_monto_cobrado, v_plan.moneda,
      p_metodo_pago, 'active', v_hoy, v_valido_hasta, v_ahora,
      p_receptionist_id, p_notas
    )
    RETURNING * INTO v_sub;
    v_accion := 'created';
  END IF;

  -- 3. Asiento en el ledger. Si la idempotency_key ya existe (carrera),
  --    el 23505 propaga y revierte TODO (incluida la extensión de arriba).
  INSERT INTO historial_pagos (
    usuario_id, suscripcion_id, plan_id, monto, moneda, metodo_pago,
    estado_pago, plan_nombre, plan_duracion_dias, periodo_desde, periodo_hasta,
    numero_recibo, pase_cortesia_codigo, receptionist_id, notas,
    idempotency_key, variacion_precio
  ) VALUES (
    p_usuario_id, v_sub.id, v_plan.plan_id, p_monto_cobrado, v_plan.moneda, p_metodo_pago,
    'completed', v_plan.nombre, v_plan.duracion_dias, v_sub.valido_desde, v_sub.valido_hasta,
    p_numero_recibo, p_pase_cortesia_codigo, p_receptionist_id, p_notas,
    p_idempotency_key, v_variacion
  )
  RETURNING * INTO v_pago;

  RETURN jsonb_build_object(
    'ya_procesado', false, 'accion', v_accion,
    'suscripcion', to_jsonb(v_sub), 'pago', to_jsonb(v_pago)
  );
END;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: payment_service_db; Owner: -
--

CREATE FUNCTION payment_service_db.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: historial_accesos; Type: TABLE; Schema: access_service_db; Owner: -
--

CREATE TABLE access_service_db.historial_accesos (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    usuario_id uuid NOT NULL,
    fecha_hora timestamp with time zone DEFAULT now() NOT NULL,
    acceso_concedido boolean DEFAULT true NOT NULL,
    razon_rechazo text,
    metodo_acceso text DEFAULT 'qr'::text NOT NULL,
    token_codigo text,
    CONSTRAINT historial_accesos_metodo_acceso_check CHECK ((metodo_acceso = ANY (ARRAY['qr'::text, 'ticket'::text, 'manual'::text])))
);


--
-- Name: qr_nonces_consumidos; Type: TABLE; Schema: access_service_db; Owner: -
--

CREATE TABLE access_service_db.qr_nonces_consumidos (
    nonce text NOT NULL,
    usuario_id uuid NOT NULL,
    turnstile_id text,
    consumido_en timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: tickets_visitas; Type: TABLE; Schema: access_service_db; Owner: -
--

CREATE TABLE access_service_db.tickets_visitas (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    usuario_id uuid,
    codigo_ticket text NOT NULL,
    estado text DEFAULT 'active'::text NOT NULL,
    expira_en timestamp with time zone NOT NULL,
    notas text,
    usado_at timestamp with time zone,
    usado_en timestamp with time zone,
    creado_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tickets_visitas_estado_check CHECK ((estado = ANY (ARRAY['active'::text, 'used'::text, 'valido'::text, 'usado'::text])))
);


--
-- Name: zk_device_commands; Type: TABLE; Schema: access_service_db; Owner: -
--

CREATE TABLE access_service_db.zk_device_commands (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    command_id text NOT NULL,
    serial_number text NOT NULL,
    command_string text NOT NULL,
    estado text DEFAULT 'pending'::text NOT NULL,
    return_code text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    creado_at timestamp with time zone DEFAULT now() NOT NULL,
    ejecutado_at timestamp with time zone,
    CONSTRAINT zk_device_commands_estado_check CHECK ((estado = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text])))
);


--
-- Name: passkey_credentials; Type: TABLE; Schema: auth_service_db; Owner: -
--

CREATE TABLE auth_service_db.passkey_credentials (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    credential_id text NOT NULL,
    public_key text NOT NULL,
    counter bigint DEFAULT 0 NOT NULL,
    transports text[] DEFAULT '{}'::text[] NOT NULL,
    device_name character varying(100) DEFAULT 'Dispositivo Móvil'::character varying NOT NULL,
    ultimo_uso timestamp with time zone,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pin_terminal_seq; Type: SEQUENCE; Schema: auth_service_db; Owner: -
--

CREATE SEQUENCE auth_service_db.pin_terminal_seq
    START WITH 1000
    INCREMENT BY 1
    MINVALUE 1000
    MAXVALUE 9999
    CACHE 1;


--
-- Name: refresh_tokens; Type: TABLE; Schema: auth_service_db; Owner: -
--

CREATE TABLE auth_service_db.refresh_tokens (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    family_id uuid NOT NULL,
    token_hash character varying(64) NOT NULL,
    is_consumed boolean DEFAULT false NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    device_info character varying(255),
    ip_address character varying(64),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    consumed_at timestamp with time zone,
    revoked_at timestamp with time zone
);


--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: auth_service_db; Owner: -
--

COMMENT ON TABLE auth_service_db.refresh_tokens IS 'Refresh tokens opacos con rotación, familias de sesión (multi-dispositivo) y reuse detection. El texto plano vive solo en la cookie HttpOnly del cliente.';


--
-- Name: tokens_password_reset; Type: TABLE; Schema: auth_service_db; Owner: -
--

CREATE TABLE auth_service_db.tokens_password_reset (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    usuario_id uuid NOT NULL,
    token_hash character varying(64) NOT NULL,
    expira_en timestamp with time zone DEFAULT (now() + '01:00:00'::interval) NOT NULL,
    usado boolean DEFAULT false NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE tokens_password_reset; Type: COMMENT; Schema: auth_service_db; Owner: -
--

COMMENT ON TABLE auth_service_db.tokens_password_reset IS 'Tokens de un solo uso para restablecimiento de contraseña. TTL: 1 hora.';


--
-- Name: usuarios; Type: TABLE; Schema: auth_service_db; Owner: -
--

CREATE TABLE auth_service_db.usuarios (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    email character varying(320) NOT NULL,
    password_hash character varying(72) NOT NULL,
    telefono character varying(20),
    nombre character varying(100) NOT NULL,
    apellido_paterno character varying(100) NOT NULL,
    apellido_materno character varying(100),
    fecha_nacimiento date,
    sexo_biologico public.sexo_biologico_enum DEFAULT 'no_especificado'::public.sexo_biologico_enum,
    estatura_cm numeric(5,1),
    peso_kg numeric(5,2),
    nivel_actividad public.nivel_actividad_enum DEFAULT 'sedentario'::public.nivel_actividad_enum,
    historial_clinico jsonb,
    contacto_emergencia jsonb,
    ultimo_login timestamp with time zone,
    intentos_fallidos smallint DEFAULT 0 NOT NULL,
    bloqueado_hasta timestamp with time zone,
    email_verificado boolean DEFAULT false NOT NULL,
    token_verificacion uuid DEFAULT extensions.uuid_generate_v4(),
    activo boolean DEFAULT true NOT NULL,
    rol character varying(20) DEFAULT 'miembro'::character varying NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    eliminado_en timestamp with time zone,
    pin_terminal integer,
    push_token text,
    objetivo_fitness text,
    lesiones text,
    CONSTRAINT usuarios_estatura_cm_check CHECK (((estatura_cm >= (50)::numeric) AND (estatura_cm <= (280)::numeric))),
    CONSTRAINT usuarios_intentos_fallidos_check CHECK ((intentos_fallidos >= 0)),
    CONSTRAINT usuarios_peso_kg_check CHECK (((peso_kg >= (10)::numeric) AND (peso_kg <= (500)::numeric))),
    CONSTRAINT usuarios_rol_check CHECK (((rol)::text = ANY ((ARRAY['miembro'::character varying, 'staff'::character varying, 'admin'::character varying])::text[])))
);


--
-- Name: TABLE usuarios; Type: COMMENT; Schema: auth_service_db; Owner: -
--

COMMENT ON TABLE auth_service_db.usuarios IS 'Tabla maestra de identidad del miembro. Contiene credenciales, perfil físico y datos clínicos.';


--
-- Name: COLUMN usuarios.password_hash; Type: COMMENT; Schema: auth_service_db; Owner: -
--

COMMENT ON COLUMN auth_service_db.usuarios.password_hash IS 'Hash bcrypt con work factor >= 12. Nunca almacenar texto plano.';


--
-- Name: COLUMN usuarios.historial_clinico; Type: COMMENT; Schema: auth_service_db; Owner: -
--

COMMENT ON COLUMN auth_service_db.usuarios.historial_clinico IS 'JSONB encriptado AES-256 por auth-service antes de persistir. El schema no interpreta su contenido.';


--
-- Name: COLUMN usuarios.pin_terminal; Type: COMMENT; Schema: auth_service_db; Owner: -
--

COMMENT ON COLUMN auth_service_db.usuarios.pin_terminal IS 'PIN numérico corto (1000-9999) para identificar al socio en la terminal ZKTeco SpeedFace-V5L. Asignado automáticamente al activar membresía.';


--
-- Name: catalogo_alimentos; Type: TABLE; Schema: fitness_service_db; Owner: -
--

CREATE TABLE fitness_service_db.catalogo_alimentos (
    codigo_barras character varying(30) NOT NULL,
    id_off character varying(100),
    nombre character varying(300) NOT NULL,
    nombre_generico character varying(200),
    marca character varying(150),
    categoria character varying(150),
    subcategoria character varying(150),
    ingredientes text,
    calorias_100g numeric(7,2),
    proteinas_100g numeric(6,2),
    carbohidratos_100g numeric(6,2),
    azucares_100g numeric(6,2),
    fibra_100g numeric(6,2),
    grasas_100g numeric(6,2),
    grasas_saturadas_100g numeric(6,2),
    grasas_trans_100g numeric(6,2),
    sodio_mg_100g numeric(7,2),
    calcio_mg_100g numeric(7,2),
    hierro_mg_100g numeric(7,2),
    porcion_gramos numeric(6,2),
    porciones_envase numeric(5,1),
    paises text[],
    idioma_nombre character(5) DEFAULT 'es'::bpchar,
    etiquetas text[],
    imagen_url text,
    nutriscore character(1),
    ecoscore character(1),
    completitud_score smallint DEFAULT 0 NOT NULL,
    fuente character varying(30) DEFAULT 'open_food_facts'::character varying NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    sincronizado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT catalogo_alimentos_azucares_100g_check CHECK ((azucares_100g >= (0)::numeric)),
    CONSTRAINT catalogo_alimentos_calorias_100g_check CHECK (((calorias_100g >= (0)::numeric) AND (calorias_100g <= (9000)::numeric))),
    CONSTRAINT catalogo_alimentos_carbohidratos_100g_check CHECK ((carbohidratos_100g >= (0)::numeric)),
    CONSTRAINT catalogo_alimentos_completitud_score_check CHECK (((completitud_score >= 0) AND (completitud_score <= 100))),
    CONSTRAINT catalogo_alimentos_ecoscore_check CHECK (((ecoscore = ANY (ARRAY['A'::bpchar, 'B'::bpchar, 'C'::bpchar, 'D'::bpchar, 'E'::bpchar])) OR (ecoscore IS NULL))),
    CONSTRAINT catalogo_alimentos_fibra_100g_check CHECK ((fibra_100g >= (0)::numeric)),
    CONSTRAINT catalogo_alimentos_grasas_100g_check CHECK ((grasas_100g >= (0)::numeric)),
    CONSTRAINT catalogo_alimentos_grasas_saturadas_100g_check CHECK ((grasas_saturadas_100g >= (0)::numeric)),
    CONSTRAINT catalogo_alimentos_grasas_trans_100g_check CHECK ((grasas_trans_100g >= (0)::numeric)),
    CONSTRAINT catalogo_alimentos_nutriscore_check CHECK (((nutriscore = ANY (ARRAY['A'::bpchar, 'B'::bpchar, 'C'::bpchar, 'D'::bpchar, 'E'::bpchar])) OR (nutriscore IS NULL))),
    CONSTRAINT catalogo_alimentos_proteinas_100g_check CHECK ((proteinas_100g >= (0)::numeric)),
    CONSTRAINT catalogo_alimentos_sodio_mg_100g_check CHECK ((sodio_mg_100g >= (0)::numeric))
);


--
-- Name: TABLE catalogo_alimentos; Type: COMMENT; Schema: fitness_service_db; Owner: -
--

COMMENT ON TABLE fitness_service_db.catalogo_alimentos IS 'Catálogo nutricional sincronizado desde Open Food Facts. Filtra productos de México y Latinoamérica. Valores nutricionales estandarizados por 100g según COFEPRIS/FDA.';


--
-- Name: COLUMN catalogo_alimentos.codigo_barras; Type: COMMENT; Schema: fitness_service_db; Owner: -
--

COMMENT ON COLUMN fitness_service_db.catalogo_alimentos.codigo_barras IS 'EAN-8, EAN-13 o UPC como PK string. Clave de idempotencia del seeding.';


--
-- Name: COLUMN catalogo_alimentos.completitud_score; Type: COMMENT; Schema: fitness_service_db; Owner: -
--

COMMENT ON COLUMN fitness_service_db.catalogo_alimentos.completitud_score IS 'Score 0-100 calculado durante el seed. Determina la calidad del registro. Campos que suman: calorías(20) + proteínas(15) + carbos(15) + grasas(15) + azúcares(10) + fibra(10) + sodio(10) + imagen(5).';


--
-- Name: catalogo_ejercicios; Type: TABLE; Schema: fitness_service_db; Owner: -
--

CREATE TABLE fitness_service_db.catalogo_ejercicios (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    id_wger integer NOT NULL,
    uuid_wger uuid,
    nombre character varying(200) NOT NULL,
    nombre_en character varying(200),
    descripcion text,
    categoria character varying(80),
    nivel fitness_service_db.nivel_ejercicio_enum DEFAULT 'intermedio'::fitness_service_db.nivel_ejercicio_enum,
    equipamiento text[],
    musculo_principal text[],
    musculo_secundario text[],
    region_corporal fitness_service_db.region_corporal_enum DEFAULT 'anterior'::fitness_service_db.region_corporal_enum,
    imagen_url text,
    video_url text,
    thumbnail_url text,
    fuente character varying(20) DEFAULT 'wger'::character varying NOT NULL,
    idioma_original character(2) DEFAULT 'es'::bpchar NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    sincronizado_en timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE catalogo_ejercicios; Type: COMMENT; Schema: fitness_service_db; Owner: -
--

COMMENT ON TABLE fitness_service_db.catalogo_ejercicios IS 'Biblioteca de ejercicios sincronizada desde wger Workout Manager. Los IDs de músculos siguen el estándar NSCA/ACSM definido en muscleGroups.js.';


--
-- Name: COLUMN catalogo_ejercicios.id_wger; Type: COMMENT; Schema: fitness_service_db; Owner: -
--

COMMENT ON COLUMN fitness_service_db.catalogo_ejercicios.id_wger IS 'ID numérico original de wger. PK natural para idempotencia del seeding.';


--
-- Name: COLUMN catalogo_ejercicios.equipamiento; Type: COMMENT; Schema: fitness_service_db; Owner: -
--

COMMENT ON COLUMN fitness_service_db.catalogo_ejercicios.equipamiento IS 'Array de strings descriptivos del equipo requerido. Para filtros en la app.';


--
-- Name: COLUMN catalogo_ejercicios.musculo_principal; Type: COMMENT; Schema: fitness_service_db; Owner: -
--

COMMENT ON COLUMN fitness_service_db.catalogo_ejercicios.musculo_principal IS 'Array de claves canónicas NSCA/ACSM. Indexado GIN para filtros multi-músculo.';


--
-- Name: ejercicios; Type: TABLE; Schema: fitness_service_db; Owner: -
--

CREATE TABLE fitness_service_db.ejercicios (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    nombre character varying(150) NOT NULL,
    grupo_muscular text,
    dificultad text,
    equipamiento text,
    descripcion text,
    creado_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ejercicios_dificultad_check CHECK ((dificultad = ANY (ARRAY['beginner'::text, 'intermediate'::text, 'advanced'::text])))
);


--
-- Name: progreso_fisico; Type: TABLE; Schema: fitness_service_db; Owner: -
--

CREATE TABLE fitness_service_db.progreso_fisico (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    usuario_id uuid NOT NULL,
    peso_kg numeric(5,2) NOT NULL,
    porcentaje_grasa numeric(5,2),
    masa_muscular_kg numeric(5,2),
    medidas jsonb,
    notas text,
    fecha_medicion timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: registros_nutricion; Type: TABLE; Schema: fitness_service_db; Owner: -
--

CREATE TABLE fitness_service_db.registros_nutricion (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    usuario_id uuid NOT NULL,
    fecha date DEFAULT CURRENT_DATE NOT NULL,
    comida character varying(30) DEFAULT 'desayuno'::character varying NOT NULL,
    codigo_barras character varying(30),
    nombre_alimento character varying(300) NOT NULL,
    cantidad_gramos numeric(7,2) NOT NULL,
    calorias_consumidas numeric(7,2),
    proteinas_g numeric(6,2),
    carbohidratos_g numeric(6,2),
    grasas_g numeric(6,2),
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT registros_nutricion_cantidad_gramos_check CHECK ((cantidad_gramos > (0)::numeric)),
    CONSTRAINT registros_nutricion_comida_check CHECK (((comida)::text = ANY ((ARRAY['desayuno'::character varying, 'almuerzo'::character varying, 'comida'::character varying, 'cena'::character varying, 'snack'::character varying])::text[])))
);


--
-- Name: TABLE registros_nutricion; Type: COMMENT; Schema: fitness_service_db; Owner: -
--

COMMENT ON TABLE fitness_service_db.registros_nutricion IS 'Diario nutricional del miembro. Cada fila representa 1 porción de alimento consumido.';


--
-- Name: rutina_ejercicios; Type: TABLE; Schema: fitness_service_db; Owner: -
--

CREATE TABLE fitness_service_db.rutina_ejercicios (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    rutina_id uuid NOT NULL,
    ejercicio_id uuid NOT NULL,
    series integer DEFAULT 3 NOT NULL,
    repeticiones integer DEFAULT 12 NOT NULL,
    descanso_seg integer DEFAULT 60 NOT NULL,
    orden integer NOT NULL
);


--
-- Name: rutinas; Type: TABLE; Schema: fitness_service_db; Owner: -
--

CREATE TABLE fitness_service_db.rutinas (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    usuario_id uuid NOT NULL,
    nombre character varying(150) NOT NULL,
    descripcion text,
    nivel text DEFAULT 'intermediate'::text NOT NULL,
    creado_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rutinas_nivel_check CHECK ((nivel = ANY (ARRAY['beginner'::text, 'intermediate'::text, 'advanced'::text])))
);


--
-- Name: rutinas_usuario; Type: TABLE; Schema: fitness_service_db; Owner: -
--

CREATE TABLE fitness_service_db.rutinas_usuario (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    usuario_id uuid NOT NULL,
    nombre character varying(200) NOT NULL,
    descripcion text,
    objetivo character varying(50),
    nivel fitness_service_db.nivel_ejercicio_enum DEFAULT 'intermedio'::fitness_service_db.nivel_ejercicio_enum,
    dias_por_semana smallint,
    plan_json jsonb NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    es_favorito boolean DEFAULT false NOT NULL,
    veces_completada integer DEFAULT 0 NOT NULL,
    ultima_sesion_en timestamp with time zone,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT rutinas_usuario_dias_por_semana_check CHECK (((dias_por_semana >= 1) AND (dias_por_semana <= 7)))
);


--
-- Name: TABLE rutinas_usuario; Type: COMMENT; Schema: fitness_service_db; Owner: -
--

COMMENT ON TABLE fitness_service_db.rutinas_usuario IS 'Planes de entrenamiento guardados. plan_json contiene el WorkoutPlan completo del ai-service.';


--
-- Name: historial_pagos; Type: TABLE; Schema: payment_service_db; Owner: -
--

CREATE TABLE payment_service_db.historial_pagos (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    suscripcion_id uuid,
    usuario_id uuid NOT NULL,
    monto numeric(10,2) NOT NULL,
    moneda character(3) DEFAULT 'MXN'::bpchar NOT NULL,
    metodo_pago character varying(20) DEFAULT 'cash'::character varying NOT NULL,
    estado_pago character varying(20) DEFAULT 'completed'::character varying NOT NULL,
    plan_nombre character varying(100),
    plan_duracion_dias smallint,
    periodo_desde timestamp with time zone,
    periodo_hasta timestamp with time zone,
    numero_recibo character varying(50),
    pase_cortesia_codigo character varying(40),
    receptionist_id character varying(80),
    notas text,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    stripe_event_id character varying(80),
    idempotency_key text,
    variacion_precio numeric(10,2),
    plan_id uuid,
    CONSTRAINT chk_hp_auditoria CHECK (((((metodo_pago)::text = 'stripe'::text) AND (stripe_event_id IS NOT NULL)) OR (((metodo_pago)::text <> 'stripe'::text) AND (receptionist_id IS NOT NULL)))),
    CONSTRAINT chk_hp_metodo_pago CHECK (((metodo_pago)::text = ANY ((ARRAY['cash'::character varying, 'card_terminal'::character varying, 'transfer'::character varying, 'stripe'::character varying])::text[]))),
    CONSTRAINT historial_pagos_estado_pago_check CHECK (((estado_pago)::text = ANY ((ARRAY['completed'::character varying, 'refunded'::character varying, 'voided'::character varying])::text[]))),
    CONSTRAINT historial_pagos_monto_check CHECK ((monto > (0)::numeric)),
    CONSTRAINT historial_pagos_plan_duracion_dias_check CHECK (((plan_duracion_dias IS NULL) OR (plan_duracion_dias > 0)))
);


--
-- Name: TABLE historial_pagos; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON TABLE payment_service_db.historial_pagos IS 'Ledger inmutable de pagos presenciales (efectivo/terminal) registrados en recepción. Tarea 3.4.';


--
-- Name: COLUMN historial_pagos.pase_cortesia_codigo; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON COLUMN payment_service_db.historial_pagos.pase_cortesia_codigo IS 'codigo_ticket del pase de cortesía (access_service_db.tickets_visitas) impreso para ingreso del mismo día.';


--
-- Name: COLUMN historial_pagos.stripe_event_id; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON COLUMN payment_service_db.historial_pagos.stripe_event_id IS 'ID del evento Stripe (evt_…) que generó el asiento online. Único → idempotencia.';


--
-- Name: COLUMN historial_pagos.variacion_precio; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON COLUMN payment_service_db.historial_pagos.variacion_precio IS 'monto_cobrado - precio_base_actual del plan al momento del pago. Negativo = descuento; positivo = recargo. Rastro contable.';


--
-- Name: ofertas; Type: TABLE; Schema: payment_service_db; Owner: -
--

CREATE TABLE payment_service_db.ofertas (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    nombre character varying(120) NOT NULL,
    codigo character varying(40) NOT NULL,
    tipo character varying(20) NOT NULL,
    valor numeric(10,2) NOT NULL,
    activa boolean DEFAULT true NOT NULL,
    valido_desde timestamp with time zone NOT NULL,
    valido_hasta timestamp with time zone NOT NULL,
    usos integer DEFAULT 0 NOT NULL,
    max_usos integer,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_vigencia CHECK ((valido_hasta > valido_desde)),
    CONSTRAINT ofertas_max_usos_check CHECK (((max_usos IS NULL) OR (max_usos > 0))),
    CONSTRAINT ofertas_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['porcentaje'::character varying, 'monto_fijo'::character varying, 'meses_gratis'::character varying])::text[]))),
    CONSTRAINT ofertas_usos_check CHECK ((usos >= 0)),
    CONSTRAINT ofertas_valor_check CHECK ((valor >= (0)::numeric))
);


--
-- Name: TABLE ofertas; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON TABLE payment_service_db.ofertas IS 'Ofertas/cupones de descuento gestionados desde el panel admin. RLS deny-all.';


--
-- Name: pagos; Type: TABLE; Schema: payment_service_db; Owner: -
--

CREATE TABLE payment_service_db.pagos (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    suscripcion_id uuid NOT NULL,
    usuario_id uuid NOT NULL,
    monto numeric(8,2) NOT NULL,
    moneda character(3) DEFAULT 'MXN'::bpchar NOT NULL,
    metodo_pago public.metodo_pago_enum NOT NULL,
    estado_pago character varying(30) DEFAULT 'completado'::character varying NOT NULL,
    stripe_payment_intent_id character varying(50),
    stripe_invoice_id character varying(50),
    stripe_charge_id character varying(50),
    numero_recibo character varying(50),
    notas_staff text,
    periodo_desde date NOT NULL,
    periodo_hasta date NOT NULL,
    registrado_por uuid,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pagos_estado_pago_check CHECK (((estado_pago)::text = ANY ((ARRAY['completado'::character varying, 'fallido'::character varying, 'reembolsado'::character varying, 'pendiente'::character varying])::text[]))),
    CONSTRAINT pagos_monto_check CHECK ((monto > (0)::numeric))
);


--
-- Name: TABLE pagos; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON TABLE payment_service_db.pagos IS 'Historial de transacciones. Cada renovación de suscripción genera un registro aquí.';


--
-- Name: planes; Type: TABLE; Schema: payment_service_db; Owner: -
--

CREATE TABLE payment_service_db.planes (
    plan_id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre character varying(100) NOT NULL,
    duracion_dias smallint NOT NULL,
    precio_base_actual numeric(10,2) NOT NULL,
    moneda character(3) DEFAULT 'MXN'::bpchar NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT planes_duracion_dias_check CHECK (((duracion_dias > 0) AND (duracion_dias <= 3660))),
    CONSTRAINT planes_precio_base_actual_check CHECK ((precio_base_actual >= (0)::numeric))
);


--
-- Name: COLUMN planes.precio_base_actual; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON COLUMN payment_service_db.planes.precio_base_actual IS 'Precio de referencia vigente. El cobro real puede diferir (descuentos/promos); la diferencia se registra en historial_pagos.variacion_precio para auditoría.';


--
-- Name: suscripciones; Type: TABLE; Schema: payment_service_db; Owner: -
--

CREATE TABLE payment_service_db.suscripciones (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    usuario_id uuid NOT NULL,
    plan_nombre character varying(100) NOT NULL,
    plan_precio numeric(8,2) NOT NULL,
    plan_duracion_dias smallint NOT NULL,
    valido_desde date DEFAULT CURRENT_DATE NOT NULL,
    valido_hasta date NOT NULL,
    estado public.estado_suscripcion_enum DEFAULT 'active'::public.estado_suscripcion_enum NOT NULL,
    stripe_customer_id character varying(50),
    stripe_subscription_id character varying(50),
    stripe_price_id character varying(50),
    stripe_payment_method_id character varying(50),
    stripe_status character varying(30),
    metodo_pago public.metodo_pago_enum NOT NULL,
    renovacion_automatica boolean DEFAULT true NOT NULL,
    motivo_cambio_estado text,
    suspendido_desde date,
    suspendido_hasta date,
    registrado_por uuid,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    actualizado_en timestamp with time zone DEFAULT now() NOT NULL,
    acceso_facial_revocado_en timestamp with time zone,
    razon_cancelacion text,
    razon_fallo_pago text,
    notificado_recuperacion_en timestamp with time zone,
    notificado_inactividad_en timestamp with time zone,
    monto numeric(10,2),
    moneda character varying(3) DEFAULT 'MXN'::character varying,
    ultimo_pago_en timestamp with time zone,
    proximo_pago_en timestamp with time zone,
    cancelado_en timestamp with time zone,
    CONSTRAINT chk_sus_fechas_coherentes CHECK ((valido_hasta > valido_desde)),
    CONSTRAINT chk_sus_stripe_campos CHECK ((((metodo_pago = 'stripe'::public.metodo_pago_enum) AND (stripe_customer_id IS NOT NULL)) OR (metodo_pago <> 'stripe'::public.metodo_pago_enum))),
    CONSTRAINT chk_sus_suspension_coherente CHECK ((((suspendido_desde IS NULL) AND (suspendido_hasta IS NULL)) OR ((suspendido_desde IS NOT NULL) AND (suspendido_hasta IS NOT NULL) AND (suspendido_hasta > suspendido_desde)))),
    CONSTRAINT suscripciones_plan_duracion_dias_check CHECK ((plan_duracion_dias > 0)),
    CONSTRAINT suscripciones_plan_precio_check CHECK ((plan_precio >= (0)::numeric))
);


--
-- Name: TABLE suscripciones; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON TABLE payment_service_db.suscripciones IS 'Membresías activas e históricas del miembro. Fuente de verdad para determinar si un miembro puede acceder.';


--
-- Name: COLUMN suscripciones.valido_hasta; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON COLUMN payment_service_db.suscripciones.valido_hasta IS 'CRÍTICO: Fecha exacta de expiración. Indexada. access-service la consulta vía API para validar acceso.';


--
-- Name: COLUMN suscripciones.stripe_status; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON COLUMN payment_service_db.suscripciones.stripe_status IS 'Estado reportado por Stripe en webhooks. Puede diferir del campo estado interno durante sincronización.';


--
-- Name: COLUMN suscripciones.acceso_facial_revocado_en; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON COLUMN payment_service_db.suscripciones.acceso_facial_revocado_en IS 'Marca de tiempo en que el cron de retención empujó el DELETE facial a ZKTeco por vencimiento de valido_hasta. NULL = acceso facial vigente o ya reactivado. Se limpia (vuelve a NULL) cuando la membresía se reactiva tras un pago.';


--
-- Name: webhook_events_procesados; Type: TABLE; Schema: payment_service_db; Owner: -
--

CREATE TABLE payment_service_db.webhook_events_procesados (
    event_id character varying(80) NOT NULL,
    tipo character varying(80),
    procesado_en timestamp with time zone DEFAULT now() NOT NULL,
    resultado character varying(20) DEFAULT 'ok'::character varying NOT NULL,
    CONSTRAINT webhook_events_procesados_resultado_check CHECK (((resultado)::text = ANY ((ARRAY['ok'::character varying, 'error'::character varying])::text[])))
);


--
-- Name: TABLE webhook_events_procesados; Type: COMMENT; Schema: payment_service_db; Owner: -
--

COMMENT ON TABLE payment_service_db.webhook_events_procesados IS 'Ledger de idempotencia de webhooks de Stripe. event_id = PK: el INSERT atómico previene doble procesamiento (race at-least-once).';


--
-- Name: historial_accesos historial_accesos_pkey; Type: CONSTRAINT; Schema: access_service_db; Owner: -
--

ALTER TABLE ONLY access_service_db.historial_accesos
    ADD CONSTRAINT historial_accesos_pkey PRIMARY KEY (id);


--
-- Name: qr_nonces_consumidos qr_nonces_consumidos_pkey; Type: CONSTRAINT; Schema: access_service_db; Owner: -
--

ALTER TABLE ONLY access_service_db.qr_nonces_consumidos
    ADD CONSTRAINT qr_nonces_consumidos_pkey PRIMARY KEY (nonce);


--
-- Name: tickets_visitas tickets_visitas_codigo_ticket_key; Type: CONSTRAINT; Schema: access_service_db; Owner: -
--

ALTER TABLE ONLY access_service_db.tickets_visitas
    ADD CONSTRAINT tickets_visitas_codigo_ticket_key UNIQUE (codigo_ticket);


--
-- Name: tickets_visitas tickets_visitas_pkey; Type: CONSTRAINT; Schema: access_service_db; Owner: -
--

ALTER TABLE ONLY access_service_db.tickets_visitas
    ADD CONSTRAINT tickets_visitas_pkey PRIMARY KEY (id);


--
-- Name: zk_device_commands zk_device_commands_command_id_key; Type: CONSTRAINT; Schema: access_service_db; Owner: -
--

ALTER TABLE ONLY access_service_db.zk_device_commands
    ADD CONSTRAINT zk_device_commands_command_id_key UNIQUE (command_id);


--
-- Name: zk_device_commands zk_device_commands_pkey; Type: CONSTRAINT; Schema: access_service_db; Owner: -
--

ALTER TABLE ONLY access_service_db.zk_device_commands
    ADD CONSTRAINT zk_device_commands_pkey PRIMARY KEY (id);


--
-- Name: passkey_credentials passkey_credentials_credential_id_key; Type: CONSTRAINT; Schema: auth_service_db; Owner: -
--

ALTER TABLE ONLY auth_service_db.passkey_credentials
    ADD CONSTRAINT passkey_credentials_credential_id_key UNIQUE (credential_id);


--
-- Name: passkey_credentials passkey_credentials_pkey; Type: CONSTRAINT; Schema: auth_service_db; Owner: -
--

ALTER TABLE ONLY auth_service_db.passkey_credentials
    ADD CONSTRAINT passkey_credentials_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: auth_service_db; Owner: -
--

ALTER TABLE ONLY auth_service_db.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: tokens_password_reset tokens_password_reset_pkey; Type: CONSTRAINT; Schema: auth_service_db; Owner: -
--

ALTER TABLE ONLY auth_service_db.tokens_password_reset
    ADD CONSTRAINT tokens_password_reset_pkey PRIMARY KEY (id);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: auth_service_db; Owner: -
--

ALTER TABLE ONLY auth_service_db.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: catalogo_alimentos catalogo_alimentos_pkey; Type: CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.catalogo_alimentos
    ADD CONSTRAINT catalogo_alimentos_pkey PRIMARY KEY (codigo_barras);


--
-- Name: catalogo_ejercicios catalogo_ejercicios_pkey; Type: CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.catalogo_ejercicios
    ADD CONSTRAINT catalogo_ejercicios_pkey PRIMARY KEY (id);


--
-- Name: ejercicios ejercicios_pkey; Type: CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.ejercicios
    ADD CONSTRAINT ejercicios_pkey PRIMARY KEY (id);


--
-- Name: progreso_fisico progreso_fisico_pkey; Type: CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.progreso_fisico
    ADD CONSTRAINT progreso_fisico_pkey PRIMARY KEY (id);


--
-- Name: registros_nutricion registros_nutricion_pkey; Type: CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.registros_nutricion
    ADD CONSTRAINT registros_nutricion_pkey PRIMARY KEY (id);


--
-- Name: rutina_ejercicios rutina_ejercicios_pkey; Type: CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.rutina_ejercicios
    ADD CONSTRAINT rutina_ejercicios_pkey PRIMARY KEY (id);


--
-- Name: rutinas rutinas_pkey; Type: CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.rutinas
    ADD CONSTRAINT rutinas_pkey PRIMARY KEY (id);


--
-- Name: rutinas_usuario rutinas_usuario_pkey; Type: CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.rutinas_usuario
    ADD CONSTRAINT rutinas_usuario_pkey PRIMARY KEY (id);


--
-- Name: historial_pagos historial_pagos_pkey; Type: CONSTRAINT; Schema: payment_service_db; Owner: -
--

ALTER TABLE ONLY payment_service_db.historial_pagos
    ADD CONSTRAINT historial_pagos_pkey PRIMARY KEY (id);


--
-- Name: ofertas ofertas_pkey; Type: CONSTRAINT; Schema: payment_service_db; Owner: -
--

ALTER TABLE ONLY payment_service_db.ofertas
    ADD CONSTRAINT ofertas_pkey PRIMARY KEY (id);


--
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: payment_service_db; Owner: -
--

ALTER TABLE ONLY payment_service_db.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (id);


--
-- Name: planes planes_pkey; Type: CONSTRAINT; Schema: payment_service_db; Owner: -
--

ALTER TABLE ONLY payment_service_db.planes
    ADD CONSTRAINT planes_pkey PRIMARY KEY (plan_id);


--
-- Name: suscripciones suscripciones_pkey; Type: CONSTRAINT; Schema: payment_service_db; Owner: -
--

ALTER TABLE ONLY payment_service_db.suscripciones
    ADD CONSTRAINT suscripciones_pkey PRIMARY KEY (id);


--
-- Name: webhook_events_procesados webhook_events_procesados_pkey; Type: CONSTRAINT; Schema: payment_service_db; Owner: -
--

ALTER TABLE ONLY payment_service_db.webhook_events_procesados
    ADD CONSTRAINT webhook_events_procesados_pkey PRIMARY KEY (event_id);


--
-- Name: idx_ha_token_codigo; Type: INDEX; Schema: access_service_db; Owner: -
--

CREATE INDEX idx_ha_token_codigo ON access_service_db.historial_accesos USING btree (token_codigo);


--
-- Name: idx_ha_usuario_fecha; Type: INDEX; Schema: access_service_db; Owner: -
--

CREATE INDEX idx_ha_usuario_fecha ON access_service_db.historial_accesos USING btree (usuario_id, fecha_hora DESC);


--
-- Name: idx_tv_codigo; Type: INDEX; Schema: access_service_db; Owner: -
--

CREATE INDEX idx_tv_codigo ON access_service_db.tickets_visitas USING btree (codigo_ticket);


--
-- Name: idx_zk_cmd_dispatch; Type: INDEX; Schema: access_service_db; Owner: -
--

CREATE INDEX idx_zk_cmd_dispatch ON access_service_db.zk_device_commands USING btree (serial_number, estado, creado_at);


--
-- Name: idx_passkey_user_id; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE INDEX idx_passkey_user_id ON auth_service_db.passkey_credentials USING btree (user_id);


--
-- Name: idx_refresh_tokens_family_id; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE INDEX idx_refresh_tokens_family_id ON auth_service_db.refresh_tokens USING btree (family_id);


--
-- Name: idx_refresh_tokens_token_hash; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE UNIQUE INDEX idx_refresh_tokens_token_hash ON auth_service_db.refresh_tokens USING btree (token_hash);


--
-- Name: idx_refresh_tokens_user_id; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE INDEX idx_refresh_tokens_user_id ON auth_service_db.refresh_tokens USING btree (user_id);


--
-- Name: idx_tpr_token_hash; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE INDEX idx_tpr_token_hash ON auth_service_db.tokens_password_reset USING btree (token_hash);


--
-- Name: idx_tpr_usuario_id; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE INDEX idx_tpr_usuario_id ON auth_service_db.tokens_password_reset USING btree (usuario_id);


--
-- Name: idx_usuarios_bloqueado_hasta; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE INDEX idx_usuarios_bloqueado_hasta ON auth_service_db.usuarios USING btree (bloqueado_hasta) WHERE (bloqueado_hasta IS NOT NULL);


--
-- Name: idx_usuarios_email; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE INDEX idx_usuarios_email ON auth_service_db.usuarios USING btree (email);


--
-- Name: idx_usuarios_nombre_trgm; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE INDEX idx_usuarios_nombre_trgm ON auth_service_db.usuarios USING gin (nombre public.gin_trgm_ops);


--
-- Name: uq_usuarios_email_activo; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE UNIQUE INDEX uq_usuarios_email_activo ON auth_service_db.usuarios USING btree (email) WHERE (eliminado_en IS NULL);


--
-- Name: uq_usuarios_pin_terminal; Type: INDEX; Schema: auth_service_db; Owner: -
--

CREATE UNIQUE INDEX uq_usuarios_pin_terminal ON auth_service_db.usuarios USING btree (pin_terminal) WHERE ((pin_terminal IS NOT NULL) AND (eliminado_en IS NULL));


--
-- Name: idx_alimentos_categoria_marca; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_alimentos_categoria_marca ON fitness_service_db.catalogo_alimentos USING btree (categoria, marca) WHERE (activo = true);


--
-- Name: idx_alimentos_completitud; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_alimentos_completitud ON fitness_service_db.catalogo_alimentos USING btree (completitud_score DESC) WHERE (activo = true);


--
-- Name: idx_alimentos_etiquetas_gin; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_alimentos_etiquetas_gin ON fitness_service_db.catalogo_alimentos USING gin (etiquetas);


--
-- Name: idx_alimentos_nombre_generico_trgm; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_alimentos_nombre_generico_trgm ON fitness_service_db.catalogo_alimentos USING gin (nombre_generico public.gin_trgm_ops);


--
-- Name: idx_alimentos_nombre_trgm; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_alimentos_nombre_trgm ON fitness_service_db.catalogo_alimentos USING gin (nombre public.gin_trgm_ops);


--
-- Name: idx_alimentos_paises_gin; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_alimentos_paises_gin ON fitness_service_db.catalogo_alimentos USING gin (paises);


--
-- Name: idx_ejercicios_categoria_nivel; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_ejercicios_categoria_nivel ON fitness_service_db.catalogo_ejercicios USING btree (categoria, nivel) WHERE (activo = true);


--
-- Name: idx_ejercicios_grupo; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_ejercicios_grupo ON fitness_service_db.ejercicios USING btree (grupo_muscular);


--
-- Name: idx_ejercicios_musculo_principal_gin; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_ejercicios_musculo_principal_gin ON fitness_service_db.catalogo_ejercicios USING gin (musculo_principal);


--
-- Name: idx_ejercicios_musculo_secundario_gin; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_ejercicios_musculo_secundario_gin ON fitness_service_db.catalogo_ejercicios USING gin (musculo_secundario);


--
-- Name: idx_ejercicios_nombre_trgm; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_ejercicios_nombre_trgm ON fitness_service_db.catalogo_ejercicios USING gin (nombre public.gin_trgm_ops);


--
-- Name: idx_nutricion_usuario_fecha; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_nutricion_usuario_fecha ON fitness_service_db.registros_nutricion USING btree (usuario_id, fecha DESC);


--
-- Name: idx_progreso_usuario; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_progreso_usuario ON fitness_service_db.progreso_fisico USING btree (usuario_id, fecha_medicion DESC);


--
-- Name: idx_rutina_ej_rutina; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_rutina_ej_rutina ON fitness_service_db.rutina_ejercicios USING btree (rutina_id);


--
-- Name: idx_rutinas_usuario; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_rutinas_usuario ON fitness_service_db.rutinas USING btree (usuario_id, creado_at DESC);


--
-- Name: idx_rutinas_usuario_id; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE INDEX idx_rutinas_usuario_id ON fitness_service_db.rutinas_usuario USING btree (usuario_id, creado_en DESC) WHERE (activo = true);


--
-- Name: uq_ejercicios_id_wger; Type: INDEX; Schema: fitness_service_db; Owner: -
--

CREATE UNIQUE INDEX uq_ejercicios_id_wger ON fitness_service_db.catalogo_ejercicios USING btree (id_wger);


--
-- Name: idx_hp_recepcionista_fecha; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_hp_recepcionista_fecha ON payment_service_db.historial_pagos USING btree (receptionist_id, creado_en DESC);


--
-- Name: idx_hp_usuario_fecha; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_hp_usuario_fecha ON payment_service_db.historial_pagos USING btree (usuario_id, creado_en DESC);


--
-- Name: idx_ofertas_activas; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_ofertas_activas ON payment_service_db.ofertas USING btree (activa) WHERE (activa = true);


--
-- Name: idx_pagos_suscripcion_id; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_pagos_suscripcion_id ON payment_service_db.pagos USING btree (suscripcion_id);


--
-- Name: idx_pagos_usuario_id; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_pagos_usuario_id ON payment_service_db.pagos USING btree (usuario_id, creado_en DESC);


--
-- Name: idx_sus_por_vencer; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_sus_por_vencer ON payment_service_db.suscripciones USING btree (valido_hasta, estado) WHERE (estado = ANY (ARRAY['activa'::public.estado_suscripcion_enum, 'suspendida'::public.estado_suscripcion_enum]));


--
-- Name: idx_sus_stripe_customer_id; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_sus_stripe_customer_id ON payment_service_db.suscripciones USING btree (stripe_customer_id) WHERE (stripe_customer_id IS NOT NULL);


--
-- Name: idx_sus_usuario_estado_vigencia; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_sus_usuario_estado_vigencia ON payment_service_db.suscripciones USING btree (usuario_id, estado, valido_hasta DESC);


--
-- Name: idx_suscripciones_pendiente_revocacion_facial; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_suscripciones_pendiente_revocacion_facial ON payment_service_db.suscripciones USING btree (valido_hasta) WHERE (acceso_facial_revocado_en IS NULL);


--
-- Name: idx_webhook_events_procesado_en; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE INDEX idx_webhook_events_procesado_en ON payment_service_db.webhook_events_procesados USING btree (procesado_en);


--
-- Name: uq_historial_pagos_idempotency; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE UNIQUE INDEX uq_historial_pagos_idempotency ON payment_service_db.historial_pagos USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: uq_hp_numero_recibo; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE UNIQUE INDEX uq_hp_numero_recibo ON payment_service_db.historial_pagos USING btree (numero_recibo) WHERE (numero_recibo IS NOT NULL);


--
-- Name: uq_hp_stripe_event; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE UNIQUE INDEX uq_hp_stripe_event ON payment_service_db.historial_pagos USING btree (stripe_event_id) WHERE (stripe_event_id IS NOT NULL);


--
-- Name: uq_ofertas_codigo; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE UNIQUE INDEX uq_ofertas_codigo ON payment_service_db.ofertas USING btree (lower((codigo)::text));


--
-- Name: uq_pagos_stripe_payment_intent; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE UNIQUE INDEX uq_pagos_stripe_payment_intent ON payment_service_db.pagos USING btree (stripe_payment_intent_id) WHERE (stripe_payment_intent_id IS NOT NULL);


--
-- Name: uq_sus_stripe_subscription_id; Type: INDEX; Schema: payment_service_db; Owner: -
--

CREATE UNIQUE INDEX uq_sus_stripe_subscription_id ON payment_service_db.suscripciones USING btree (stripe_subscription_id) WHERE (stripe_subscription_id IS NOT NULL);


--
-- Name: passkey_credentials trg_passkey_credentials_updated_at; Type: TRIGGER; Schema: auth_service_db; Owner: -
--

CREATE TRIGGER trg_passkey_credentials_updated_at BEFORE UPDATE ON auth_service_db.passkey_credentials FOR EACH ROW EXECUTE FUNCTION auth_service_db.set_updated_at();


--
-- Name: usuarios trg_usuarios_updated_at; Type: TRIGGER; Schema: auth_service_db; Owner: -
--

CREATE TRIGGER trg_usuarios_updated_at BEFORE UPDATE ON auth_service_db.usuarios FOR EACH ROW EXECUTE FUNCTION auth_service_db.set_updated_at();


--
-- Name: catalogo_alimentos trg_alimentos_updated_at; Type: TRIGGER; Schema: fitness_service_db; Owner: -
--

CREATE TRIGGER trg_alimentos_updated_at BEFORE UPDATE ON fitness_service_db.catalogo_alimentos FOR EACH ROW EXECUTE FUNCTION fitness_service_db.set_updated_at();


--
-- Name: catalogo_ejercicios trg_ejercicios_updated_at; Type: TRIGGER; Schema: fitness_service_db; Owner: -
--

CREATE TRIGGER trg_ejercicios_updated_at BEFORE UPDATE ON fitness_service_db.catalogo_ejercicios FOR EACH ROW EXECUTE FUNCTION fitness_service_db.set_updated_at();


--
-- Name: rutinas_usuario trg_rutinas_updated_at; Type: TRIGGER; Schema: fitness_service_db; Owner: -
--

CREATE TRIGGER trg_rutinas_updated_at BEFORE UPDATE ON fitness_service_db.rutinas_usuario FOR EACH ROW EXECUTE FUNCTION fitness_service_db.set_updated_at();


--
-- Name: historial_pagos trg_hp_no_mutation; Type: TRIGGER; Schema: payment_service_db; Owner: -
--

CREATE TRIGGER trg_hp_no_mutation BEFORE DELETE OR UPDATE ON payment_service_db.historial_pagos FOR EACH ROW EXECUTE FUNCTION payment_service_db.deny_ledger_mutation();


--
-- Name: suscripciones trg_sus_updated_at; Type: TRIGGER; Schema: payment_service_db; Owner: -
--

CREATE TRIGGER trg_sus_updated_at BEFORE UPDATE ON payment_service_db.suscripciones FOR EACH ROW EXECUTE FUNCTION payment_service_db.set_updated_at();


--
-- Name: tokens_password_reset fk_tpr_usuario; Type: FK CONSTRAINT; Schema: auth_service_db; Owner: -
--

ALTER TABLE ONLY auth_service_db.tokens_password_reset
    ADD CONSTRAINT fk_tpr_usuario FOREIGN KEY (usuario_id) REFERENCES auth_service_db.usuarios(id) ON DELETE CASCADE;


--
-- Name: passkey_credentials passkey_credentials_user_id_fkey; Type: FK CONSTRAINT; Schema: auth_service_db; Owner: -
--

ALTER TABLE ONLY auth_service_db.passkey_credentials
    ADD CONSTRAINT passkey_credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth_service_db.usuarios(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: auth_service_db; Owner: -
--

ALTER TABLE ONLY auth_service_db.refresh_tokens
    ADD CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth_service_db.usuarios(id) ON DELETE CASCADE;


--
-- Name: rutina_ejercicios rutina_ejercicios_ejercicio_id_fkey; Type: FK CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.rutina_ejercicios
    ADD CONSTRAINT rutina_ejercicios_ejercicio_id_fkey FOREIGN KEY (ejercicio_id) REFERENCES fitness_service_db.ejercicios(id) ON DELETE RESTRICT;


--
-- Name: rutina_ejercicios rutina_ejercicios_rutina_id_fkey; Type: FK CONSTRAINT; Schema: fitness_service_db; Owner: -
--

ALTER TABLE ONLY fitness_service_db.rutina_ejercicios
    ADD CONSTRAINT rutina_ejercicios_rutina_id_fkey FOREIGN KEY (rutina_id) REFERENCES fitness_service_db.rutinas(id) ON DELETE CASCADE;


--
-- Name: pagos fk_pagos_suscripcion; Type: FK CONSTRAINT; Schema: payment_service_db; Owner: -
--

ALTER TABLE ONLY payment_service_db.pagos
    ADD CONSTRAINT fk_pagos_suscripcion FOREIGN KEY (suscripcion_id) REFERENCES payment_service_db.suscripciones(id) ON DELETE RESTRICT;


--
-- Name: historial_accesos deny_all_access_historial; Type: POLICY; Schema: access_service_db; Owner: -
--

CREATE POLICY deny_all_access_historial ON access_service_db.historial_accesos USING (false);


--
-- Name: tickets_visitas deny_all_access_tickets; Type: POLICY; Schema: access_service_db; Owner: -
--

CREATE POLICY deny_all_access_tickets ON access_service_db.tickets_visitas USING (false);


--
-- Name: zk_device_commands deny_all_access_zk_commands; Type: POLICY; Schema: access_service_db; Owner: -
--

CREATE POLICY deny_all_access_zk_commands ON access_service_db.zk_device_commands USING (false);


--
-- Name: qr_nonces_consumidos deny_all_qr_nonces; Type: POLICY; Schema: access_service_db; Owner: -
--

CREATE POLICY deny_all_qr_nonces ON access_service_db.qr_nonces_consumidos USING (false);


--
-- Name: historial_accesos; Type: ROW SECURITY; Schema: access_service_db; Owner: -
--

ALTER TABLE access_service_db.historial_accesos ENABLE ROW LEVEL SECURITY;

--
-- Name: qr_nonces_consumidos; Type: ROW SECURITY; Schema: access_service_db; Owner: -
--

ALTER TABLE access_service_db.qr_nonces_consumidos ENABLE ROW LEVEL SECURITY;

--
-- Name: historial_accesos svc_access_rw; Type: POLICY; Schema: access_service_db; Owner: -
--

CREATE POLICY svc_access_rw ON access_service_db.historial_accesos TO svc_access USING (true) WITH CHECK (true);


--
-- Name: qr_nonces_consumidos svc_access_rw; Type: POLICY; Schema: access_service_db; Owner: -
--

CREATE POLICY svc_access_rw ON access_service_db.qr_nonces_consumidos TO svc_access USING (true) WITH CHECK (true);


--
-- Name: tickets_visitas svc_access_rw; Type: POLICY; Schema: access_service_db; Owner: -
--

CREATE POLICY svc_access_rw ON access_service_db.tickets_visitas TO svc_access USING (true) WITH CHECK (true);


--
-- Name: zk_device_commands svc_access_rw; Type: POLICY; Schema: access_service_db; Owner: -
--

CREATE POLICY svc_access_rw ON access_service_db.zk_device_commands TO svc_access USING (true) WITH CHECK (true);


--
-- Name: historial_accesos svc_payment_ro_h; Type: POLICY; Schema: access_service_db; Owner: -
--

CREATE POLICY svc_payment_ro_h ON access_service_db.historial_accesos FOR SELECT TO svc_payment USING (true);


--
-- Name: tickets_visitas; Type: ROW SECURITY; Schema: access_service_db; Owner: -
--

ALTER TABLE access_service_db.tickets_visitas ENABLE ROW LEVEL SECURITY;

--
-- Name: zk_device_commands; Type: ROW SECURITY; Schema: access_service_db; Owner: -
--

ALTER TABLE access_service_db.zk_device_commands ENABLE ROW LEVEL SECURITY;

--
-- Name: passkey_credentials deny_all_auth_passkey; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY deny_all_auth_passkey ON auth_service_db.passkey_credentials USING (false);


--
-- Name: refresh_tokens deny_all_auth_refresh_tokens; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY deny_all_auth_refresh_tokens ON auth_service_db.refresh_tokens USING (false);


--
-- Name: tokens_password_reset deny_all_auth_tokens; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY deny_all_auth_tokens ON auth_service_db.tokens_password_reset USING (false);


--
-- Name: usuarios deny_all_auth_usuarios; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY deny_all_auth_usuarios ON auth_service_db.usuarios USING (false);


--
-- Name: passkey_credentials; Type: ROW SECURITY; Schema: auth_service_db; Owner: -
--

ALTER TABLE auth_service_db.passkey_credentials ENABLE ROW LEVEL SECURITY;

--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: auth_service_db; Owner: -
--

ALTER TABLE auth_service_db.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: usuarios svc_access_ro; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY svc_access_ro ON auth_service_db.usuarios FOR SELECT TO svc_access USING (true);


--
-- Name: passkey_credentials svc_auth_rw; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY svc_auth_rw ON auth_service_db.passkey_credentials TO svc_auth USING (true) WITH CHECK (true);


--
-- Name: refresh_tokens svc_auth_rw; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY svc_auth_rw ON auth_service_db.refresh_tokens TO svc_auth USING (true) WITH CHECK (true);


--
-- Name: tokens_password_reset svc_auth_rw; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY svc_auth_rw ON auth_service_db.tokens_password_reset TO svc_auth USING (true) WITH CHECK (true);


--
-- Name: usuarios svc_auth_rw; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY svc_auth_rw ON auth_service_db.usuarios TO svc_auth USING (true) WITH CHECK (true);


--
-- Name: usuarios svc_payment_ro_u; Type: POLICY; Schema: auth_service_db; Owner: -
--

CREATE POLICY svc_payment_ro_u ON auth_service_db.usuarios FOR SELECT TO svc_payment USING (true);


--
-- Name: tokens_password_reset; Type: ROW SECURITY; Schema: auth_service_db; Owner: -
--

ALTER TABLE auth_service_db.tokens_password_reset ENABLE ROW LEVEL SECURITY;

--
-- Name: usuarios; Type: ROW SECURITY; Schema: auth_service_db; Owner: -
--

ALTER TABLE auth_service_db.usuarios ENABLE ROW LEVEL SECURITY;

--
-- Name: catalogo_alimentos; Type: ROW SECURITY; Schema: fitness_service_db; Owner: -
--

ALTER TABLE fitness_service_db.catalogo_alimentos ENABLE ROW LEVEL SECURITY;

--
-- Name: catalogo_ejercicios; Type: ROW SECURITY; Schema: fitness_service_db; Owner: -
--

ALTER TABLE fitness_service_db.catalogo_ejercicios ENABLE ROW LEVEL SECURITY;

--
-- Name: ejercicios deny_all_fitness_ejercicios; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY deny_all_fitness_ejercicios ON fitness_service_db.ejercicios USING (false);


--
-- Name: progreso_fisico deny_all_fitness_progreso; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY deny_all_fitness_progreso ON fitness_service_db.progreso_fisico USING (false);


--
-- Name: rutina_ejercicios deny_all_fitness_rutina_ej; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY deny_all_fitness_rutina_ej ON fitness_service_db.rutina_ejercicios USING (false);


--
-- Name: rutinas deny_all_fitness_rutinas; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY deny_all_fitness_rutinas ON fitness_service_db.rutinas USING (false);


--
-- Name: registros_nutricion deny_nutricion; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY deny_nutricion ON fitness_service_db.registros_nutricion USING (false);


--
-- Name: rutinas_usuario deny_rutinas; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY deny_rutinas ON fitness_service_db.rutinas_usuario USING (false);


--
-- Name: ejercicios; Type: ROW SECURITY; Schema: fitness_service_db; Owner: -
--

ALTER TABLE fitness_service_db.ejercicios ENABLE ROW LEVEL SECURITY;

--
-- Name: progreso_fisico; Type: ROW SECURITY; Schema: fitness_service_db; Owner: -
--

ALTER TABLE fitness_service_db.progreso_fisico ENABLE ROW LEVEL SECURITY;

--
-- Name: catalogo_alimentos read_catalogo_alimentos; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY read_catalogo_alimentos ON fitness_service_db.catalogo_alimentos FOR SELECT USING ((activo = true));


--
-- Name: catalogo_ejercicios read_catalogo_ejercicios; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY read_catalogo_ejercicios ON fitness_service_db.catalogo_ejercicios FOR SELECT USING ((activo = true));


--
-- Name: registros_nutricion; Type: ROW SECURITY; Schema: fitness_service_db; Owner: -
--

ALTER TABLE fitness_service_db.registros_nutricion ENABLE ROW LEVEL SECURITY;

--
-- Name: rutina_ejercicios; Type: ROW SECURITY; Schema: fitness_service_db; Owner: -
--

ALTER TABLE fitness_service_db.rutina_ejercicios ENABLE ROW LEVEL SECURITY;

--
-- Name: rutinas; Type: ROW SECURITY; Schema: fitness_service_db; Owner: -
--

ALTER TABLE fitness_service_db.rutinas ENABLE ROW LEVEL SECURITY;

--
-- Name: rutinas_usuario; Type: ROW SECURITY; Schema: fitness_service_db; Owner: -
--

ALTER TABLE fitness_service_db.rutinas_usuario ENABLE ROW LEVEL SECURITY;

--
-- Name: catalogo_alimentos svc_fitness_ro_a; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY svc_fitness_ro_a ON fitness_service_db.catalogo_alimentos FOR SELECT TO svc_fitness USING (true);


--
-- Name: ejercicios svc_fitness_ro_e; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY svc_fitness_ro_e ON fitness_service_db.ejercicios FOR SELECT TO svc_fitness USING (true);


--
-- Name: progreso_fisico svc_fitness_rw_p; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY svc_fitness_rw_p ON fitness_service_db.progreso_fisico TO svc_fitness USING (true) WITH CHECK (true);


--
-- Name: rutinas svc_fitness_rw_r; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY svc_fitness_rw_r ON fitness_service_db.rutinas TO svc_fitness USING (true) WITH CHECK (true);


--
-- Name: rutina_ejercicios svc_fitness_rw_re; Type: POLICY; Schema: fitness_service_db; Owner: -
--

CREATE POLICY svc_fitness_rw_re ON fitness_service_db.rutina_ejercicios TO svc_fitness USING (true) WITH CHECK (true);


--
-- Name: historial_pagos deny_all_historial_pagos; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY deny_all_historial_pagos ON payment_service_db.historial_pagos USING (false) WITH CHECK (false);


--
-- Name: ofertas deny_all_ofertas; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY deny_all_ofertas ON payment_service_db.ofertas USING (false);


--
-- Name: pagos deny_all_payment_pagos; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY deny_all_payment_pagos ON payment_service_db.pagos USING (false);


--
-- Name: suscripciones deny_all_payment_suscripciones; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY deny_all_payment_suscripciones ON payment_service_db.suscripciones USING (false);


--
-- Name: webhook_events_procesados deny_all_webhook_events; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY deny_all_webhook_events ON payment_service_db.webhook_events_procesados USING (false) WITH CHECK (false);


--
-- Name: historial_pagos; Type: ROW SECURITY; Schema: payment_service_db; Owner: -
--

ALTER TABLE payment_service_db.historial_pagos ENABLE ROW LEVEL SECURITY;

--
-- Name: ofertas; Type: ROW SECURITY; Schema: payment_service_db; Owner: -
--

ALTER TABLE payment_service_db.ofertas ENABLE ROW LEVEL SECURITY;

--
-- Name: pagos; Type: ROW SECURITY; Schema: payment_service_db; Owner: -
--

ALTER TABLE payment_service_db.pagos ENABLE ROW LEVEL SECURITY;

--
-- Name: suscripciones; Type: ROW SECURITY; Schema: payment_service_db; Owner: -
--

ALTER TABLE payment_service_db.suscripciones ENABLE ROW LEVEL SECURITY;

--
-- Name: suscripciones svc_access_ro_sub; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY svc_access_ro_sub ON payment_service_db.suscripciones FOR SELECT TO svc_access USING (true);


--
-- Name: historial_pagos svc_payment_rw; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY svc_payment_rw ON payment_service_db.historial_pagos TO svc_payment USING (true) WITH CHECK (true);


--
-- Name: ofertas svc_payment_rw; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY svc_payment_rw ON payment_service_db.ofertas TO svc_payment USING (true) WITH CHECK (true);


--
-- Name: suscripciones svc_payment_rw; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY svc_payment_rw ON payment_service_db.suscripciones TO svc_payment USING (true) WITH CHECK (true);


--
-- Name: webhook_events_procesados svc_payment_rw; Type: POLICY; Schema: payment_service_db; Owner: -
--

CREATE POLICY svc_payment_rw ON payment_service_db.webhook_events_procesados TO svc_payment USING (true) WITH CHECK (true);


--
-- Name: webhook_events_procesados; Type: ROW SECURITY; Schema: payment_service_db; Owner: -
--

ALTER TABLE payment_service_db.webhook_events_procesados ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict 1qck7LEPlDCx8fLWUafu61nN06d5MvvYYjnH3zdVrYSuFFj0wC3Mp5ajBE1XGtx

