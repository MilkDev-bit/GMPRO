#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@file services/reception-hardware-controller/python/qr_scanner_listener.py
@description Escucha de forma exclusiva al lector de código QR omnidireccional USB/Serie.
Intercepta las lecturas en segundo plano para evitar que el texto se filtre o se escriba
en otras aplicaciones abiertas por el recepcionista en la computadora del mostrador.
INCLUYE RECONEXIÓN AUTOMÁTICA DE PUERTOS (Auto-Healing cada 3s).
"""

import sys
import time
import logging
import threading
from typing import Callable, Optional
import serial

import config

logger = logging.getLogger("HardwareController.QrListener")

try:
    import evdev
    from evdev import ecodes
    EVDEV_AVAILABLE = True
except ImportError:
    EVDEV_AVAILABLE = False


class QrScannerListener:
    """
    Escuchador y capturador de eventos del lector QR USB.
    • Garantiza captura exclusiva (`exclusive=True` o `device.grab()`).
    • Auto-Healing: Si el cable USB es desconectado o el dispositivo se reinicia, el bucle
      supervisor intenta reconectarse en segundo plano cada 3 segundos sin colapsar la app.
    """
    def __init__(self, on_code_scanned_callback: Callable[[str], None]):
        self.on_code_scanned = on_code_scanned_callback
        self._running = False
        self._connected = False
        self._thread: Optional[threading.Thread] = None
        self._auto_heal_thread: Optional[threading.Thread] = None
        self._serial_conn: Optional[serial.Serial] = None
        self._evdev_device = None
        self._mode = config.QR_READER_MODE.lower()

    def start(self) -> bool:
        """Inicia el hilo de escucha y el supervisor de auto-healing en segundo plano."""
        if self._running:
            return True

        self._running = True
        
        # Intentar primera conexión
        self._attempt_connect()

        # Iniciar supervisor de reconexión automática (Auto-Healing)
        self._auto_heal_thread = threading.Thread(
            target=self._auto_heal_loop,
            daemon=True,
            name="QrAutoHealer"
        )
        self._auto_heal_thread.start()
        return True

    def _attempt_connect(self) -> bool:
        """Intenta abrir y escuchar el dispositivo según el modo configurado."""
        if self._connected:
            return True

        if self._mode == "evdev_hid":
            if not EVDEV_AVAILABLE:
                logger.error("❌ [Lector QR] 'evdev' no disponible. Cambiando a modo serial/emulación.")
                self._mode = "serial"
            else:
                return self._start_evdev_grab()

        if self._mode == "serial":
            return self._start_serial_exclusive()

        if not self._thread or not self._thread.is_alive():
            logger.warning(f"⚠️ [Lector QR] Modo '{self._mode}' simulado en consola.")
            self._thread = threading.Thread(target=self._console_loop, daemon=True, name="QrConsoleLoop")
            self._thread.start()
            self._connected = True
        return True

    def _auto_heal_loop(self):
        """Supervisor en segundo plano: revisa cada 3 segundos si la conexión se perdió."""
        while self._running:
            time.sleep(3.0)
            if not self._connected and self._running:
                logger.warning("🔄 [Auto-Healing QR] Lector QR no conectado o perdido. Intentando reconectar en 3 segundos...")
                self._attempt_connect()

    def _start_serial_exclusive(self) -> bool:
        """Abre el puerto Serial/COM en modo exclusivo."""
        try:
            self._serial_conn = serial.Serial(
                port=config.QR_SERIAL_PORT,
                baudrate=config.QR_SERIAL_BAUDRATE,
                timeout=0.2,
                exclusive=True if sys.platform != "win32" else False
            )
            logger.info(f"📟 [Lector QR Serial Auto-Healing] Conectado en modo EXCLUSIVO a {config.QR_SERIAL_PORT} @ {config.QR_SERIAL_BAUDRATE} bps")
            self._connected = True
            self._thread = threading.Thread(target=self._serial_loop, daemon=True, name="QrSerialLoop")
            self._thread.start()
            return True
        except Exception as e:
            logger.debug(f"⏳ [Lector QR Serial] Esperando reconexión serie ({e})...")
            self._connected = False
            return False

    def _serial_loop(self):
        """Bucle de lectura continua sobre el buffer serial del lector QR."""
        buffer = ""
        while self._running and self._connected and self._serial_conn and self._serial_conn.is_open:
            try:
                if self._serial_conn.in_waiting > 0:
                    raw_bytes = self._serial_conn.read(self._serial_conn.in_waiting)
                    try:
                        text_chunk = raw_bytes.decode("utf-8", errors="ignore")
                    except Exception:
                        text_chunk = raw_bytes.decode("latin-1", errors="ignore")
                    
                    buffer += text_chunk
                    
                    if "\n" in buffer or "\r" in buffer:
                        lines = buffer.replace("\r", "\n").split("\n")
                        for line in lines[:-1]:
                            code = line.strip()
                            if code:
                                logger.info(f"⚡ [Lector QR] Código interceptado: '{code}' (Longitud: {len(code)})")
                                self._dispatch_code(code)
                        buffer = lines[-1]
                else:
                    time.sleep(0.02)
            except Exception as e:
                if self._running:
                    logger.error(f"❌ [Lector QR Serial] Desconexión o error I/O detectado ({e}). Disparando Auto-Healing...")
                    self._connected = False
                    self._close_serial_safe()
                    break

    def _close_serial_safe(self):
        if self._serial_conn:
            try:
                self._serial_conn.close()
            except Exception:
                pass
        self._serial_conn = None

    def _start_evdev_grab(self) -> bool:
        """[Linux evdev] Secuestra (grab) los eventos del lector USB HID."""
        try:
            self._evdev_device = evdev.InputDevice(config.QR_EVDEV_DEVICE_PATH)
            self._evdev_device.grab()
            logger.info(f"🔒 [Lector QR HID Auto-Healing] Secuestro exclusivo activado en {self._evdev_device.name}")
            self._connected = True
            self._thread = threading.Thread(target=self._evdev_loop, daemon=True, name="QrEvdevLoop")
            self._thread.start()
            return True
        except Exception as e:
            logger.debug(f"⏳ [Lector QR HID] Esperando reconexión HID en {config.QR_EVDEV_DEVICE_PATH} ({e})...")
            self._connected = False
            return False

    def _evdev_loop(self):
        """Bucle de lectura sobre eventos evdev del kernel de Linux."""
        scancodes_to_ascii = {
            ecodes.KEY_A: 'A', ecodes.KEY_B: 'B', ecodes.KEY_C: 'C', ecodes.KEY_D: 'D', ecodes.KEY_E: 'E',
            ecodes.KEY_F: 'F', ecodes.KEY_G: 'G', ecodes.KEY_H: 'H', ecodes.KEY_I: 'I', ecodes.KEY_J: 'J',
            ecodes.KEY_K: 'K', ecodes.KEY_L: 'L', ecodes.KEY_M: 'M', ecodes.KEY_N: 'N', ecodes.KEY_O: 'O',
            ecodes.KEY_P: 'P', ecodes.KEY_Q: 'Q', ecodes.KEY_R: 'R', ecodes.KEY_S: 'S', ecodes.KEY_T: 'T',
            ecodes.KEY_U: 'U', ecodes.KEY_V: 'V', ecodes.KEY_W: 'W', ecodes.KEY_X: 'X', ecodes.KEY_Y: 'Y',
            ecodes.KEY_Z: 'Z', ecodes.KEY_1: '1', ecodes.KEY_2: '2', ecodes.KEY_3: '3', ecodes.KEY_4: '4',
            ecodes.KEY_5: '5', ecodes.KEY_6: '6', ecodes.KEY_7: '7', ecodes.KEY_8: '8', ecodes.KEY_9: '9',
            ecodes.KEY_0: '0', ecodes.KEY_MINUS: '-', ecodes.KEY_EQUAL: '=', ecodes.KEY_SPACE: ' '
        }
        buffer = []
        try:
            for event in self._evdev_device.read_loop():
                if not self._running:
                    break
                if event.type == ecodes.EV_KEY:
                    data = evdev.categorize(event)
                    if data.keystate == evdev.KeyEvent.key_down:
                        if event.code == ecodes.KEY_ENTER or event.code == ecodes.KEY_KPENTER:
                            code = "".join(buffer).strip()
                            if code:
                                logger.info(f"⚡ [Lector QR HID] Código interceptado: '{code}'")
                                self._dispatch_code(code)
                            buffer = []
                        elif event.code in scancodes_to_ascii:
                            buffer.append(scancodes_to_ascii[event.code])
        except Exception as e:
            if self._running:
                logger.error(f"❌ [Lector QR HID] Desconexión detectada en evdev ({e}). Activando Auto-Healing...")
                self._connected = False
                if self._evdev_device:
                    try:
                        self._evdev_device.ungrab()
                    except Exception:
                        pass
                self._evdev_device = None

    def _console_loop(self):
        """Bucle de consola en desarrollo."""
        logger.info("⌨️ [Lector QR Simulación] Escribe un código y presiona ENTER para probar:")
        while self._running and self._connected:
            try:
                line = sys.stdin.readline()
                if not line:
                    time.sleep(0.1)
                    continue
                code = line.strip()
                if code:
                    logger.info(f"⚡ [Simulación QR] Código ingresado: '{code}'")
                    self._dispatch_code(code)
            except Exception:
                break

    def _dispatch_code(self, code: str):
        threading.Thread(
            target=self.on_code_scanned,
            args=(code,),
            daemon=True,
            name=f"Dispatch-{time.time()}"
        ).start()

    def stop(self):
        """Detiene la escucha y libera los bloqueos exclusivos sobre los puertos."""
        self._running = False
        self._connected = False
        self._close_serial_safe()
        if self._evdev_device and EVDEV_AVAILABLE:
            try:
                self._evdev_device.ungrab()
                logger.info("🔓 [Lector QR HID] Dispositivo liberado del secuestro kernel (ungrab).")
            except Exception:
                pass
        self._evdev_device = None
