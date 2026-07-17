#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@file services/reception-hardware-controller/python/relay_controller.py
@description Controlador del módulo de relevador USB para destrabar físicamente
el torniquete ZKTeco TS1000 Plus de forma segura, libre de condiciones de carrera (Mutex Lock)
y con RECONEXIÓN AUTOMÁTICA DE PUERTOS (Auto-Healing cada 3s).
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
    • Asegura pulso exacto de 1.0s para el paso de un solo usuario.
    • Auto-Healing: Si el cable USB se desconecta o falla el puerto COM, inicia un
      bucle de reconexión en segundo plano cada 3 segundos sin congelar el hilo principal.
    """
    def __init__(self):
        self._lock = threading.Lock()
        self._serial_conn: Optional[serial.Serial] = None
        self._running = False
        self._auto_heal_thread: Optional[threading.Thread] = None

    def start(self) -> bool:
        """Inicia el relevador y el supervisor de auto-reconexión en segundo plano."""
        self._running = True
        connected = self.connect()
        
        # Iniciar hilo de monitoreo continuo (Auto-Healing) cada 3 segundos
        self._auto_heal_thread = threading.Thread(
            target=self._auto_heal_loop,
            daemon=True,
            name="RelayAutoHealer"
        )
        self._auto_heal_thread.start()
        return connected

    def connect(self) -> bool:
        """Establece conexión con el puerto serie del relevador USB."""
        if config.RELAY_TYPE != "serial_hex" and config.RELAY_TYPE != "serial_dtr":
            if self._serial_conn is None:
                logger.warning(f"💡 [Relevador] Tipo '{config.RELAY_TYPE}' en modo simulación GPIO/Dummy.")
            return True

        with self._lock:
            if self._serial_conn and self._serial_conn.is_open:
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
                logger.info(f"⚡ [Relevador Auto-Healing] Conectado exitosamente al puerto {config.RELAY_SERIAL_PORT} @ {config.RELAY_SERIAL_BAUDRATE} bps")
                self._send_raw_nolock(config.RELAY_HEX_CLOSE_CMD)
                return True
            except Exception as e:
                self._serial_conn = None
                return False

    def _auto_heal_loop(self):
        """
        Bucle en segundo plano que vigila el estado del puerto cada 3 segundos.
        Si detecta desconexión, intenta reabrir el puerto sin bloquear el sistema central.
        """
        while self._running:
            time.sleep(3.0)
            if config.RELAY_TYPE in ("serial_hex", "serial_dtr"):
                is_open = False
                with self._lock:
                    is_open = (self._serial_conn is not None and self._serial_conn.is_open)
                
                if not is_open and self._running:
                    logger.warning(f"🔄 [Auto-Healing Relevador] Puerto {config.RELAY_SERIAL_PORT} desconectado. Intentando reconectar en segundo plano...")
                    self.connect()

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
                success_open = self._send_raw_nolock(config.RELAY_HEX_OPEN_CMD)
                time.sleep(pulse_time)
                success_close = self._send_raw_nolock(config.RELAY_HEX_CLOSE_CMD)
                
                if success_open and success_close:
                    logger.info("🔒 [Relevador] Pulso completado y circuito reabierto correctamente.")
                    return True
                else:
                    logger.warning("⚠️ [Relevador] Error de I/O serie durante el pulso. Activando auto-healing para siguiente intento.")
                    self._mark_disconnected_nolock()
                    return False
                    
            elif config.RELAY_TYPE == "serial_dtr":
                try:
                    if self._serial_conn and self._serial_conn.is_open:
                        self._serial_conn.dtr = True
                        self._serial_conn.rts = True
                        time.sleep(pulse_time)
                        self._serial_conn.dtr = False
                        self._serial_conn.rts = False
                        logger.info("🔒 [Relevador DTR/RTS] Pulso completado.")
                        return True
                    else:
                        logger.warning("⚠️ [Relevador DTR/RTS] Puerto no disponible. Esperando auto-healing...")
                        time.sleep(pulse_time)
                        return False
                except Exception as e:
                    logger.error(f"❌ [Relevador DTR/RTS] Error en líneas de control: {e}")
                    self._mark_disconnected_nolock()
                    return False
            else:
                logger.info(f"💡 [Relevador SIMULACIÓN] Circuito CERRADO (Torniquete Liberado) -> esperando {pulse_time}s...")
                time.sleep(pulse_time)
                logger.info("💡 [Relevador SIMULACIÓN] Circuito ABIERTO (Torniquete Trabado).")
                return True

    def _send_raw_nolock(self, cmd: bytes) -> bool:
        """Envía bytes al relevador (sin adquirir mutex, debe ser invocado dentro del with self._lock)."""
        if not self._serial_conn or not self._serial_conn.is_open:
            return False
        try:
            self._serial_conn.write(cmd)
            self._serial_conn.flush()
            return True
        except Exception as e:
            logger.error(f"❌ [Relevador] Error escribiendo al puerto serie ({e}). Marcando para auto-reconexión.")
            self._mark_disconnected_nolock()
            return False

    def _mark_disconnected_nolock(self):
        """Cierra de manera segura una conexión rota para que el auto-healer actúe en 3s."""
        if self._serial_conn:
            try:
                self._serial_conn.close()
            except Exception:
                pass
        self._serial_conn = None

    def close(self):
        """Detiene el auto-healer, cierra el puerto serie y asegura el bloqueo del torniquete al salir."""
        self._running = False
        with self._lock:
            if self._serial_conn and self._serial_conn.is_open:
                try:
                    self._send_raw_nolock(config.RELAY_HEX_CLOSE_CMD)
                    self._serial_conn.close()
                    logger.info("⚡ [Relevador] Puerto serie cerrado correctamente.")
                except Exception as e:
                    logger.error(f"❌ [Relevador] Error al cerrar conexión: {e}")
            self._serial_conn = None
