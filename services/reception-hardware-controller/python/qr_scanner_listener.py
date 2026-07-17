#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@file services/reception-hardware-controller/python/qr_scanner_listener.py
@description Escucha de forma exclusiva al lector de código QR omnidireccional USB/Serie.
Intercepta las lecturas en segundo plano para evitar que el texto se filtre o se escriba
en otras aplicaciones abiertas por el recepcionista en la computadora del mostrador.
"""

import sys
import time
import logging
import threading
from typing import Callable, Optional
import serial

import config

logger = logging.getLogger("HardwareController.QrListener")

# Intentar importar evdev en entornos Linux para captura exclusiva HID (device.grab())
try:
    import evdev
    from evdev import ecodes
    EVDEV_AVAILABLE = True
except ImportError:
    EVDEV_AVAILABLE = False


class QrScannerListener:
    """
    Escuchador y capturador de eventos del lector QR USB.
    Garantiza captura exclusiva (Sin filtraciones hacia el teclado del sistema / Excel / Navegador):
      • Modo Serial/COM: Abre el puerto con `exclusive=True` para adueñarse del flujo de datos.
      • Modo evdev HID (Linux): Llama a `device.grab()` para secuestrar los eventos del kernel.
    """
    def __init__(self, on_code_scanned_callback: Callable[[str], None]):
        self.on_code_scanned = on_code_scanned_callback
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._serial_conn: Optional[serial.Serial] = None
        self._evdev_device = None

    def start(self) -> bool:
        """Inicia el hilo de escucha en segundo plano según el modo configurado."""
        if self._running:
            return True

        self._running = True
        mode = config.QR_READER_MODE.lower()

        if mode == "evdev_hid":
            if not EVDEV_AVAILABLE:
                logger.error("❌ [Lector QR] 'evdev' no está instalado o no es Linux. Cambiando a modo serial/emulación.")
                mode = "serial"
            else:
                return self._start_evdev_grab()

        if mode == "serial":
            return self._start_serial_exclusive()

        logger.warning(f"⚠️ [Lector QR] Modo '{mode}' no reconocido. Iniciando en modo consola para pruebas rápidas.")
        self._thread = threading.Thread(target=self._console_loop, daemon=True, name="QrConsoleLoop")
        self._thread.start()
        return True

    def _start_serial_exclusive(self) -> bool:
        """Abre el puerto Serial/COM en modo exclusivo para interceptar el lector QR sin filtraciones."""
        try:
            # En Python 3.3+, exclusive=True asegura que ninguna otra aplicación pueda abrir ni escuchar el puerto
            self._serial_conn = serial.Serial(
                port=config.QR_SERIAL_PORT,
                baudrate=config.QR_SERIAL_BAUDRATE,
                timeout=0.2,
                exclusive=True if sys.platform != "win32" else False # En Windows el bloqueo es implícito por defecto
            )
            logger.info(f"📟 [Lector QR Serial] Conectado en modo EXCLUSIVO a {config.QR_SERIAL_PORT} @ {config.QR_SERIAL_BAUDRATE} bps")
            
            self._thread = threading.Thread(target=self._serial_loop, daemon=True, name="QrSerialLoop")
            self._thread.start()
            return True
        except Exception as e:
            logger.error(f"❌ [Lector QR Serial] No se pudo abrir el puerto serie {config.QR_SERIAL_PORT}: {e}")
            logger.info("💡 [Lector QR] ¿El lector está en modo USB Virtual COM? Verifique el manual del escáner o cambie la ruta en config.py.")
            return False

    def _serial_loop(self):
        """Bucle de lectura continua sobre el buffer serial del lector QR."""
        buffer = ""
        while self._running and self._serial_conn and self._serial_conn.is_open:
            try:
                if self._serial_conn.in_waiting > 0:
                    raw_bytes = self._serial_conn.read(self._serial_conn.in_waiting)
                    try:
                        text_chunk = raw_bytes.decode("utf-8", errors="ignore")
                    except Exception:
                        text_chunk = raw_bytes.decode("latin-1", errors="ignore")
                    
                    buffer += text_chunk
                    
                    # Si el lector manda salto de línea (\r o \n), se completó la lectura de un código
                    if "\n" in buffer or "\r" in buffer:
                        lines = buffer.replace("\r", "\n").split("\n")
                        for line in lines[:-1]:
                            code = line.strip()
                            if code:
                                logger.info(f"⚡ [Lector QR] Código interceptado: '{code}' (Longitud: {len(code)})")
                                self._dispatch_code(code)
                        buffer = lines[-1] # Conservar residuo de la siguiente lectura
                else:
                    time.sleep(0.02)
            except Exception as e:
                if self._running:
                    logger.error(f"❌ [Lector QR Serial] Error leyendo datos del buffer: {e}")
                    time.sleep(0.5)

    def _start_evdev_grab(self) -> bool:
        """
        [Linux evdev] Secuestra (grab) los eventos del lector USB HID a nivel de kernel.
        Evita que las lecturas se escriban en X11/Wayland o en campos de texto abiertos de la recepción.
        """
        try:
            self._evdev_device = evdev.InputDevice(config.QR_EVDEV_DEVICE_PATH)
            # ¡CRÍTICO PARA TAREA 5.1! device.grab() le indica al kernel de Linux que asigne
            # uso EXCLUSIVO de este lector USB al script, bloqueando los eventos de teclado al sistema.
            self._evdev_device.grab()
            logger.info(f"🔒 [Lector QR HID] Secuestro exclusivo (grab) activado en {self._evdev_device.name} ({config.QR_EVDEV_DEVICE_PATH})")
            
            self._thread = threading.Thread(target=self._evdev_loop, daemon=True, name="QrEvdevLoop")
            self._thread.start()
            return True
        except Exception as e:
            logger.error(f"❌ [Lector QR HID] Error al capturar dispositivo {config.QR_EVDEV_DEVICE_PATH}: {e}")
            return False

    def _evdev_loop(self):
        """Bucle de lectura sobre eventos del kernel de Linux (evdev)."""
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
                    if data.keystate == evdev.KeyEvent.key_down: # Solo presionado
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
                logger.error(f"❌ [Lector QR HID] Error en bucle evdev: {e}")

    def _console_loop(self):
        """Bucle de entrada por consola (stdin) para pruebas locales en desarrollo sin hardware USB."""
        logger.info("⌨️ [Lector QR Simulación] Escribe un código QR en la consola y presiona ENTER para probar:")
        while self._running:
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
        """Envía el código al callback en un hilo separado para no bloquear la lectura del siguiente QR."""
        threading.Thread(
            target=self.on_code_scanned,
            args=(code,),
            daemon=True,
            name=f"Dispatch-{time.time()}"
        ).start()

    def stop(self):
        """Detiene la escucha y libera los bloqueos exclusivos sobre los puertos."""
        self._running = False
        if self._serial_conn and self._serial_conn.is_open:
            try:
                self._serial_conn.close()
            except Exception:
                pass
        if self._evdev_device and EVDEV_AVAILABLE:
            try:
                self._evdev_device.ungrab()
                logger.info("🔓 [Lector QR HID] Dispositivo liberado del secuestro kernel (ungrab).")
            except Exception:
                pass
