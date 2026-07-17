#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@file services/reception-hardware-controller/python/thermal_printer.py
@description Controlador ESC/POS para impresora térmica USB de 80mm en mostrador de recepción.
Genera tickets profesionales de pase diario con código QR óptico de alta densidad.
"""

import logging
from datetime import datetime
from typing import Optional
import config

logger = logging.getLogger("HardwareController.Printer")

# Intentar importar la librería oficial python-escpos
try:
    from escpos.printer import Usb, Serial, File
    from escpos.exceptions import USBNotFoundError, Error as EscposError
    ESCPOS_AVAILABLE = True
except ImportError:
    ESCPOS_AVAILABLE = False
    logger.warning("⚠️ Librería 'python-escpos' no instalada. La impresión térmica funcionará en modo simulación/log.")

class ThermalPrinterController:
    """
    Controlador de impresora térmica ESC/POS de 80mm.
    Soporta conexión USB directa (VID/PID) o Serial COM.
    Imprime cabecera nítida, metadatos legibles y código QR óptico listo para torniquetes.
    """
    def __init__(self):
        self._printer = None

    def connect(self) -> bool:
        """Inicializa y verifica la conexión con la impresora térmica USB o Serial."""
        if not ESCPOS_AVAILABLE:
            logger.info("🖨️ [Impresora] Modo de simulación activo (python-escpos ausente).")
            return True

        try:
            if config.PRINTER_MODE == "usb":
                logger.info(f"🖨️ [Impresora] Buscando impresora USB VID=0x{config.PRINTER_USB_VID:04x}, PID=0x{config.PRINTER_USB_PID:04x}...")
                self._printer = Usb(
                    config.PRINTER_USB_VID,
                    config.PRINTER_USB_PID,
                    in_ep=config.PRINTER_USB_IN_EP,
                    out_ep=config.PRINTER_USB_OUT_EP
                )
                logger.info("🖨️ [Impresora] Conexión USB ESC/POS establecida exitosamente.")
                return True
            elif config.PRINTER_MODE == "serial":
                self._printer = Serial(devfile=config.PRINTER_SERIAL_PORT, baudrate=config.PRINTER_SERIAL_BAUD)
                logger.info(f"🖨️ [Impresora] Conexión Serial ESC/POS en {config.PRINTER_SERIAL_PORT} establecida.")
                return True
            else:
                logger.info("🖨️ [Impresora] Modo archivo/dummy seleccionado en configuración.")
                return True
        except Exception as e:
            logger.error(f"❌ [Impresora] No se pudo conectar con impresora física ({e}). Se usará modo simulación en consola.")
            self._printer = None
            return False

    def print_daily_visit_ticket(
        self,
        ticket_code: String if 'String' in globals() else str,
        qr_string: str,
        validity_hours: int = 24,
        user_name: str = "Visita GymPro",
        notes: Optional[str] = None
    ) -> bool:
        """
        Imprime el ticket físico de pase de visita diaria en papel térmico de 80mm:
        • Cabecera centrada y en doble ancho/alto.
        • Líneas divisorias y fecha exacta de emisión.
        • Código QR óptico (ESC/POS nativo o imagen renderizada) de 180x180 px mínimo.
        • Instrucciones de uso y corte de papel automático.
        """
        now_str = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        logger.info(f"🖨️ [Impresora] Imprimiendo pase diario '{ticket_code}' para '{user_name}'...")

        # Si no hay impresora conectada (o modo dev), imprimir representación visual en consola log
        if not self._printer:
            self._simulate_console_print(ticket_code, qr_string, validity_hours, user_name, notes, now_str)
            return True

        try:
            p = self._printer
            
            # Inicializar impresora y alinear al centro
            p.hw("INIT")
            p.set(align="center")

            # ── CABECERA ──────────────────────────────────────────────────────────
            p.set(align="center", double_width=True, double_height=True, bold=True)
            p.text("GYMPRO AI FITNESS\n")
            p.set(align="center", normal_textsize=True, bold=False)
            p.text("SISTEMA BIOMÉTRICO Y ACCESO\n")
            p.text("--------------------------------\n")

            # ── TÍTULO DEL TICKET ─────────────────────────────────────────────────
            p.set(align="center", bold=True)
            p.text("PASE DE VISITA DIARIA\n\n")

            # ── METADATOS (Alineado a la izquierda) ───────────────────────────────
            p.set(align="left", normal_textsize=True)
            p.text(f"Socio/Visita : {user_name[:24]}\n")
            p.text(f"Emitido      : {now_str}\n")
            p.text(f"Vigencia     : {validity_hours} Horas\n")
            p.text(f"Código Pase  : {ticket_code}\n")
            if notes:
                p.text(f"Notas        : {notes[:32]}\n")
            p.text("--------------------------------\n\n")

            # ── CÓDIGO QR ÓPTICO (Nativo ESC/POS) ────────────────────────────────
            p.set(align="center")
            # El parámetro model=2, ec=0 (L) o 1 (M), size=8 es ideal para lectores láser/ópticos de torniquete
            p.qr(qr_string, ec=0, size=8, model=2, center=True)
            p.text("\n")

            # ── PIE DE PÁGINA ────────────────────────────────────────────────────
            p.set(align="center", bold=True)
            p.text(f"[{ticket_code}]\n\n")
            p.set(align="center", normal_textsize=True, bold=False)
            p.text("Presente este código en la lectora\n")
            p.text("del torniquete para ingresar.\n")
            p.text("Válido para 1 solo ingreso.\n\n")
            p.text("www.gympro-ai.com\n\n\n")

            # Corte de papel automático (corte parcial o completo)
            p.cut(mode="PART")
            logger.info("✅ [Impresora] Ticket físico impreso y cortado exitosamente.")
            return True
        except Exception as e:
            logger.error(f"❌ [Impresora] Error al imprimir comandos ESC/POS: {e}")
            return False

    def _simulate_console_print(self, code: str, qr: str, hours: int, name: str, notes: Optional[str], date_str: str):
        """Imprime en consola un bosquejo ASCII del ticket para debugging y desarrollo."""
        sep = "=" * 36
        line = "-" * 36
        print(f"\n{sep}")
        print("        GYMPRO AI FITNESS")
        print("     PASE DE VISITA DIARIA (80mm)")
        print(f"{sep}")
        print(f" Socio/Visita : {name}")
        print(f" Emitido      : {date_str}")
        print(f" Vigencia     : {hours} Horas")
        print(f" Código       : {code}")
        if notes:
            print(f" Notas        : {notes}")
        print(f"{line}")
        print("     [ CÓDIGO QR ÓPTICO ESC/POS ]")
        print(f"          QR DATA -> {qr[:24]}...")
        print(f"{line}")
        print("  Presenta este ticket en torniquete")
        print(f"{sep}\n")

    def close(self):
        """Cierra el manejador de impresora al apagar el servicio."""
        if self._printer:
            try:
                self._printer.close()
            except Exception:
                pass
            self._printer = None
