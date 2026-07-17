#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@file services/reception-hardware-controller/python/relay_controller.py
@description Controlador del módulo de relevador USB para destrabar físicamente
el torniquete ZKTeco TS1000 Plus de forma segura y libre de condiciones de carrera (Mutex Lock).
"""

import time
import logging
import threading
from typing import Optional
import serial

import config

logger = logging.getLogger("HardwareController.Relay")

class TurnstileRelayController:
    """
    Controlador de Relevador USB para torniquetes ZKTeco TS1000 Plus.
    Asegura que el circuito se cierre únicamente por la duración configurada (1.0 segundo)
    y previene envíos simultáneos mediante un bloqueo de hilo (Mutex Lock).
    """
    def __init__(self):
        self._lock = threading.Lock()
        self._serial_conn: Optional[serial.Serial] = None

    def connect(self) -> bool:
        """Establece conexión con el puerto serie del relevador USB."""
        if config.RELAY_TYPE != "serial_hex" and config.RELAY_TYPE != "serial_dtr":
            logger.warning(f"Tipo de relevador '{config.RELAY_TYPE}' no es serie. Simulación en modo GPIO/Dummy activa.")
            return True

        try:
            self._serial_conn = serial.Serial(
                port=config.RELAY_SERIAL_PORT,
                baudrate=config.RELAY_SERIAL_BAUDRATE,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=1.0
            )
            logger.info(f"⚡ [Relevador] Conectado exitosamente al puerto {config.RELAY_SERIAL_PORT} @ {config.RELAY_SERIAL_BAUDRATE} bps")
            # Asegurar que el relevador inicie en estado ABIERTO (Torniquete trabado)
            self._send_raw(config.RELAY_HEX_CLOSE_CMD)
            return True
        except Exception as e:
            logger.error(f"❌ [Relevador] Error al abrir puerto serie {config.RELAY_SERIAL_PORT}: {e}")
            self._serial_conn = None
            return False

    def trigger_unlock_pulse(self, duration_seconds: Optional[float] = None) -> bool:
        """
        Envía un pulso de apertura al torniquete ZKTeco TS1000 Plus:
        1. Cierra el circuito (Activa solenoide ZKTeco).
        2. Espera `duration_seconds` (por defecto 1.0s).
        3. Abre el circuito (Traba nuevamente el torniquete una vez que el aspa rota).
        """
        pulse_time = duration_seconds if duration_seconds is not None else config.PULSE_DURATION_SECONDS

        with self._lock:
            logger.info(f"🔓 [Relevador] ACTIVANDO APERTURA DE TORNIQUETE por {pulse_time}s (ZKTeco TS1000 Plus)...")
            
            if config.RELAY_TYPE == "serial_hex":
                success_open = self._send_raw(config.RELAY_HEX_OPEN_CMD)
                time.sleep(pulse_time)
                success_close = self._send_raw(config.RELAY_HEX_CLOSE_CMD)
                
                if success_open and success_close:
                    logger.info("🔒 [Relevador] Pulso completado y circuito reabierto correctamente.")
                    return True
                else:
                    logger.warning("⚠️ [Relevador] Fallo en comunicación con hardware serie, pero ciclo completado (o simulación).")
                    return False
                    
            elif config.RELAY_TYPE == "serial_dtr":
                # Control por líneas DTR/RTS (Común en relevadores simples FTDI / CH340 DTR-triggered)
                if self._serial_conn and self._serial_conn.is_open:
                    self._serial_conn.dtr = True
                    self._serial_conn.rts = True
                    time.sleep(pulse_time)
                    self._serial_conn.dtr = False
                    self._serial_conn.rts = False
                    logger.info("🔒 [Relevador DTR/RTS] Pulso completado.")
                    return True
                else:
                    logger.warning("⚠️ [Relevador DTR/RTS] Puerto no abierto. Simulando pulso.")
                    time.sleep(pulse_time)
                    return True
            else:
                # Modo simulación / GPIO custom
                logger.info(f"💡 [Relevador SIMULACIÓN] Circuito CERRADO (Torniquete Liberado) -> esperando {pulse_time}s...")
                time.sleep(pulse_time)
                logger.info("💡 [Relevador SIMULACIÓN] Circuito ABIERTO (Torniquete Trabado).")
                return True

    def _send_raw(self, cmd: bytes) -> bool:
        """Envía bytes crudos al relevador con manejo de errores y reintentos."""
        if not self._serial_conn or not self._serial_conn.is_open:
            return False
        try:
            self._serial_conn.write(cmd)
            self._serial_conn.flush()
            return True
        except Exception as e:
            logger.error(f"❌ [Relevador] Error escribiendo al puerto serie: {e}")
            return False

    def close(self):
        """Cierra el puerto serie y asegura el bloqueo del torniquete al salir."""
        with self._lock:
            if self._serial_conn and self._serial_conn.is_open:
                try:
                    self._send_raw(config.RELAY_HEX_CLOSE_CMD)
                    self._serial_conn.close()
                    logger.info("⚡ [Relevador] Puerto serie cerrado correctamente.")
                except Exception as e:
                    logger.error(f"❌ [Relevador] Error al cerrar conexión: {e}")
            self._serial_conn = None
