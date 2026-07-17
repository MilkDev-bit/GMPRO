#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@file services/reception-hardware-controller/python/access_api_client.py
@description Cliente HTTP para comunicarse de forma segura con el access-service en Railway.
Envia tokens escaneados por la lectora QR del mostrador y retorna el estado de autorización.
"""

import time
import logging
from typing import Dict, Any, Tuple
import requests

import config

logger = logging.getLogger("HardwareController.ApiClient")

class RailwayAccessApiClient:
    """
    Cliente API para validar tokens de acceso escaneados (QR móvil dinámico o Ticket de visita)
    contra el microservicio de accesos alojado en Railway.
    Incluye autenticación por API Key (TURNSTILE_API_KEY) y reintentos ante fallos de red fugaces.
    """
    def __init__(self):
        self.base_url = config.RAILWAY_ACCESS_SERVICE_URL.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update({
            "X-Turnstile-API-Key": config.TURNSTILE_API_KEY,
            "X-Turnstile-Id": config.TURNSTILE_ID,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": f"GymPro-Reception-Hardware/1.0 ({config.TURNSTILE_ID})"
        })

    def validate_scanned_code(self, raw_token: str) -> Tuple[bool, Dict[str, Any], str]:
        """
        Analiza el token recibido y lo envía al endpoint adecuado en Railway:
        • Si inicia con 'GP-' o tiene formato de ticket -> /validate-ticket
        • De lo contrario (AES-256 cifrado de app móvil) -> /validate-qr

        Retorna:
          (acceso_concedido: bool, respuesta_data: dict, mensaje_o_razon: str)
        """
        cleaned_token = raw_token.strip()
        if not cleaned_token:
            return False, {}, "Token vacío escaneado."

        # Determinar si es un pase de visita único o un QR dinámico móvil
        is_ticket = cleaned_token.upper().startswith("GP-") or (len(cleaned_token) == 15 and "-" in cleaned_token)
        endpoint = f"{self.base_url}/validate-ticket" if is_ticket else f"{self.base_url}/validate-qr"
        payload = {"codigo_ticket": cleaned_token} if is_ticket else {"token_qr": cleaned_token}

        logger.info(f"🌐 [Railway API] Enviando {'Ticket' if is_ticket else 'QR Dinámico'} a {endpoint} ...")

        # Intentar petición HTTP con timeout corto de 3.5s para no hacer lento el torniquete
        try:
            start_t = time.time()
            response = self.session.post(endpoint, json=payload, timeout=3.5)
            elapsed_ms = int((time.time() - start_t) * 1000)

            data = {}
            try:
                data = response.json()
            except Exception:
                data = {"error": response.text}

            # Caso 1: Acceso Concedido (HTTP 200)
            if response.status_code == 200 and data.get("success") is True:
                resp_data = data.get("data", {})
                acceso = resp_data.get("acceso_concedido", False) or resp_data.get("apertura_torniquete", False)
                msg = resp_data.get("mensaje", "Acceso autorizado.")
                logger.info(f"✅ [Railway API] ({elapsed_ms}ms) RESPUESTA 200 OK -> Acceso: {acceso} | {msg}")
                return acceso, resp_data, msg

            # Caso 2: Pago requerido o membresía vencida (HTTP 402 / 403)
            elif response.status_code in (402, 403, 409):
                error_msg = data.get("error") or data.get("data", {}).get("motivo_bloqueo") or f"Rechazado HTTP {response.status_code}"
                logger.warning(f"🚫 [Railway API] ({elapsed_ms}ms) ACCESO RECHAZADO ({response.status_code}): {error_msg}")
                return False, data.get("data", {}), error_msg

            # Caso 3: Error del servidor o token malformado (HTTP 400 / 500)
            else:
                error_msg = data.get("error", f"HTTP {response.status_code}")
                logger.error(f"❌ [Railway API] ({elapsed_ms}ms) Error en servidor: {error_msg}")
                return False, data, f"Error del servidor ({response.status_code}): {error_msg}"

        except requests.exceptions.Timeout:
            logger.error("⏱️ [Railway API] Timeout conectando con el servidor en Railway (3.5s expirados).")
            return False, {}, "Tiempo de espera agotado al conectar con el servidor central."
        except requests.exceptions.ConnectionError as ce:
            logger.error(f"🔌 [Railway API] Error de red o sin conexión a internet: {ce}")
            return False, {}, "Sin conexión de red con el servidor en la nube."
        except Exception as e:
            logger.error(f"❌ [Railway API] Excepción inesperada en llamada HTTP: {e}")
            return False, {}, f"Error interno en controlador: {str(e)[:50]}"
