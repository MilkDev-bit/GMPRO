#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@file services/reception-hardware-controller/python/config.py
@description Configuración centralizada para el controlador de hardware en la recepción del gimnasio.
Maneja puertos COM/USB del lector QR, relevador de torniquete ZKTeco TS1000 y la impresora térmica de 80mm.
"""

import os
from pathlib import Path

# ── 1. CONFIGURACIÓN DE CONEXIÓN CON RAILWAY (ACCESS-SERVICE) ─────────────────
# URL base del microservicio de accesos en Railway (o localhost en desarrollo)
RAILWAY_ACCESS_SERVICE_URL = os.getenv(
    "RAILWAY_ACCESS_SERVICE_URL", 
    "https://access-service.gympro.railway.app/api/v1/access"
)

# API Key de alta seguridad para autenticar el hardware con el microservicio
TURNSTILE_API_KEY = os.getenv("TURNSTILE_API_KEY", "turnstile_secret_key_prod_2026")

# Identificador físico de este torniquete/recepción
TURNSTILE_ID = os.getenv("TURNSTILE_ID", "recepcion_torniquete_1")

# ── 2. CONFIGURACIÓN DEL LECTOR DE CÓDIGOS QR OMNIDIRECCIONAL ────────────────
# Modo de operación del lector QR: 'serial' (Puerto COM/tty) o 'evdev_hid' (Grab exclusivo teclado USB Linux)
QR_READER_MODE = os.getenv("QR_READER_MODE", "serial") # Opciones: 'serial', 'evdev_hid'

# Puerto Serial para Lector QR en emulación COM (Ej. COM3 en Windows, /dev/ttyACM0 o /dev/ttyUSB0 en Linux)
QR_SERIAL_PORT = os.getenv("QR_SERIAL_PORT", "/dev/ttyACM0" if os.name != "nt" else "COM3")
QR_SERIAL_BAUDRATE = int(os.getenv("QR_SERIAL_BAUDRATE", "9600"))

# Si QR_READER_MODE == 'evdev_hid' (Linux), ruta al device node o ID del teclado lector QR
# Ejemplo: /dev/input/by-id/usb-Honeywell_Imaging__Inc._Honeywell_CM_Scanner-event-kbd
QR_EVDEV_DEVICE_PATH = os.getenv(
    "QR_EVDEV_DEVICE_PATH", 
    "/dev/input/by-id/usb-BarCode_Scanner_Barcode_Reader-event-kbd"
)

# ── 3. CONFIGURACIÓN DEL MÓDULO DE RELEVADOR USB (TORNIQUETE ZKTECO TS1000) ───
# Tipo de relevador: 'serial_hex' (LCUS-1/CH340), 'serial_dtr' (Bitbang DTR/RTS) o 'gpio'
RELAY_TYPE = os.getenv("RELAY_TYPE", "serial_hex")

# Puerto Serial/COM donde está conectado el relevador del torniquete ZKTeco
RELAY_SERIAL_PORT = os.getenv("RELAY_SERIAL_PORT", "/dev/ttyUSB1" if os.name != "nt" else "COM4")
RELAY_SERIAL_BAUDRATE = int(os.getenv("RELAY_SERIAL_BAUDRATE", "9600"))

# Comandos Hexadecimales para relevadores tipo LCUS-1 / CH340 (Canal 1)
RELAY_HEX_OPEN_CMD = bytes.fromhex(os.getenv("RELAY_HEX_OPEN_CMD", "A00101A2"))  # Cierra circuito COM-NO
RELAY_HEX_CLOSE_CMD = bytes.fromhex(os.getenv("RELAY_HEX_CLOSE_CMD", "A00100A1")) # Abre circuito COM-NO

# Tiempo exacto (segundos) en que el circuito permanece cerrado para permitir el paso por el torniquete
PULSE_DURATION_SECONDS = float(os.getenv("PULSE_DURATION_SECONDS", "1.0"))

# ── 4. CONFIGURACIÓN DE LA IMPRESORA TÉRMICA USB DE 80MM (ESC/POS) ───────────
# Modo de impresora: 'usb' (Directo por VID/PID via PyUSB), 'serial' (COM) o 'file' (lp/lpr)
PRINTER_MODE = os.getenv("PRINTER_MODE", "usb")

# Vendor ID y Product ID en formato Hexadecimal (Ej. Epson TM-T20III VID=0x04b8, PID=0x0e28)
PRINTER_USB_VID = int(os.getenv("PRINTER_USB_VID", "0x04b8"), 16)
PRINTER_USB_PID = int(os.getenv("PRINTER_USB_PID", "0x0e28"), 16)

# Endpoint y dimensiones
PRINTER_USB_IN_EP = int(os.getenv("PRINTER_USB_IN_EP", "0x81"), 16)
PRINTER_USB_OUT_EP = int(os.getenv("PRINTER_USB_OUT_EP", "0x01"), 16)
PRINTER_PAPER_WIDTH_MM = int(os.getenv("PRINTER_PAPER_WIDTH_MM", "80"))

# Puerto serial si PRINTER_MODE == 'serial'
PRINTER_SERIAL_PORT = os.getenv("PRINTER_SERIAL_PORT", "/dev/ttyUSB2" if os.name != "nt" else "COM5")
PRINTER_SERIAL_BAUD = int(os.getenv("PRINTER_SERIAL_BAUD", "19200"))
