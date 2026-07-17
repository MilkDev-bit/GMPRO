#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@file services/reception-hardware-controller/python/thermal_printer.py
@description Controlador ESC/POS para impresora térmica USB de 80mm en mostrador de recepción.
INCLUYE:
  • Reconexión Automática (Auto-Healing cada 3s).
  • MANEJO DE COLA DE IMPRESIÓN SORDA: Si la impresora se queda sin papel o se apaga,
    las peticiones no bloquean el servidor central; los tickets fallidos se guardan localmente
    en 'failed_tickets.jsonl' para revisión o re-impresión automática al recuperar línea.
"""

import os
import json
import time
import logging
import threading
from datetime import datetime
from typing import Optional, Tuple
import config

logger = logging.getLogger("HardwareController.Printer")

try:
    from escpos.printer import Usb, Serial, File
    from escpos.exceptions import USBNotFoundError, Error as EscposError
    ESCPOS_AVAILABLE = True
except ImportError:
    ESCPOS_AVAILABLE = False
    logger.warning("⚠️ Librería 'python-escpos' no instalada. La impresora trabajará en modo simulación.")

# Archivo de cola local sorda para no bloquear base de datos ni servidor central
FAILED_TICKETS_LOG_PATH = os.path.join(os.path.dirname(__file__), "logs", "failed_tickets.jsonl")


class ThermalPrinterController:
    """
    Controlador de impresora térmica ESC/POS de 80mm con Cola Sorda y Auto-Healing.
    """
    def __init__(self):
        self._printer = None
        self._lock = threading.Lock()
        self._running = False
        self._auto_heal_thread: Optional[threading.Thread] = None
        self._ensure_logs_dir()

    def _ensure_logs_dir(self):
        os.makedirs(os.path.dirname(FAILED_TICKETS_LOG_PATH), exist_ok=True)

    def start(self) -> bool:
        """Inicia el controlador e hilo de Auto-Healing en segundo plano."""
        self._running = True
        connected = self.connect()

        self._auto_heal_thread = threading.Thread(
            target=self._auto_heal_loop,
            daemon=True,
            name="PrinterAutoHealer"
        )
        self._auto_heal_thread.start()
        return connected

    def connect(self) -> bool:
        """Inicializa y verifica la conexión con la impresora térmica USB o Serial."""
        if not ESCPOS_AVAILABLE:
            if self._printer is None:
                logger.info("🖨️ [Impresora] Modo simulación ESC/POS activo (sin python-escpos).")
            return True

        with self._lock:
            if self._printer is not None:
                return True

            try:
                if config.PRINTER_MODE == "usb":
                    self._printer = Usb(
                        config.PRINTER_USB_VID,
                        config.PRINTER_USB_PID,
                        in_ep=config.PRINTER_USB_IN_EP,
                        out_ep=config.PRINTER_USB_OUT_EP
                    )
                    logger.info("🖨️ [Impresora Auto-Healing] Conexión USB ESC/POS establecida exitosamente.")
                    return True
                elif config.PRINTER_MODE == "serial":
                    self._printer = Serial(devfile=config.PRINTER_SERIAL_PORT, baudrate=config.PRINTER_SERIAL_BAUD)
                    logger.info(f"🖨️ [Impresora Auto-Healing] Conexión Serial ESC/POS en {config.PRINTER_SERIAL_PORT} establecida.")
                    return True
                else:
                    return True
            except Exception as e:
                logger.debug(f"⏳ [Impresora] Esperando impresora térmica en línea ({e})...")
                self._printer = None
                return False

    def _auto_heal_loop(self):
        """
        Bucle en segundo plano:
        • Revisa cada 3s si la impresora está desconectada para reabrirla.
        • Si se reconecta exitosamente, intenta purgar (imprimir) la cola sorda de tickets fallidos.
        """
        while self._running:
            time.sleep(3.0)
            if config.PRINTER_MODE in ("usb", "serial") and ESCPOS_AVAILABLE:
                is_connected = False
                with self._lock:
                    is_connected = (self._printer is not None)

                if not is_connected and self._running:
                    reconnected = self.connect()
                    if reconnected:
                        logger.info("🔄 [Auto-Healing Impresora] Impresora recuperada en línea. Revisando cola sorda...")
                        self.flush_offline_queue()

    def print_daily_visit_ticket(
        self,
        ticket_code: str,
        qr_string: str,
        validity_hours: int = 24,
        user_name: str = "Visita GymPro",
        notes: Optional[str] = None
    ) -> Tuple[bool, str]:
        """
        Intenta imprimir el ticket físico de pase diario.
        Retorna (True, "printed") si imprimió físicamente.
        Retorna (True, "queued_offline") si la impresora no tenía papel/apagada y se guardó en log sordo.
        ¡No lanza excepciones fatales para no bloquear el hilo central ni la base de datos!
        """
        now_str = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        logger.info(f"🖨️ [Impresora] Solicitada impresión de pase '{ticket_code}' para '{user_name}'...")

        if not ESCPOS_AVAILABLE or config.PRINTER_MODE not in ("usb", "serial"):
            self._simulate_console_print(ticket_code, qr_string, validity_hours, user_name, notes, now_str)
            return True, "simulated"

        with self._lock:
            if not self._printer:
                # Intentar reconexión exprés
                if not self.connect():
                    logger.warning("⚠️ [Impresora Sorda] Impresora desconectada o sin energía. Encolando en 'failed_tickets.jsonl'...")
                    self._enqueue_silent_ticket(ticket_code, qr_string, validity_hours, user_name, notes, "IMPRESORA_APAGADA")
                    return True, "queued_offline"

            try:
                p = self._printer
                p.hw("INIT")
                p.set(align="center")

                # Cabecera
                p.set(align="center", double_width=True, double_height=True, bold=True)
                p.text("GYMPRO AI FITNESS\n")
                p.set(align="center", normal_textsize=True, bold=False)
                p.text("SISTEMA BIOMETRICO Y ACCESO\n")
                p.text("--------------------------------\n")

                # Título
                p.set(align="center", bold=True)
                p.text("PASE DE VISITA DIARIA\n\n")

                # Metadatos
                p.set(align="left", normal_textsize=True)
                p.text(f"Socio/Visita : {user_name[:24]}\n")
                p.text(f"Emitido      : {now_str}\n")
                p.text(f"Vigencia     : {validity_hours} Horas\n")
                p.text(f"Codigo Pase  : {ticket_code}\n")
                if notes:
                    p.text(f"Notas        : {notes[:32]}\n")
                p.text("--------------------------------\n\n")

                # QR Óptico
                p.set(align="center")
                p.qr(qr_string, ec=0, size=8, model=2, center=True)
                p.text("\n")

                # Pie
                p.set(align="center", bold=True)
                p.text(f"[{ticket_code}]\n\n")
                p.set(align="center", normal_textsize=True, bold=False)
                p.text("Presente este codigo en la lectora\n")
                p.text("del torniquete para ingresar.\n")
                p.text("Valido para 1 solo ingreso.\n\n")
                p.text("www.gympro-ai.com\n\n\n")

                p.cut(mode="PART")
                logger.info("✅ [Impresora] Ticket impreso y cortado exitosamente.")
                return True, "printed"
            except Exception as e:
                logger.error(f"❌ [Impresora Sorda] Error al imprimir ESC/POS ({e}: ¿Sin papel / Tapa abierta?). Encolando localmente...")
                self._mark_printer_dead_nolock()
                self._enqueue_silent_ticket(ticket_code, qr_string, validity_hours, user_name, notes, str(e))
                return True, "queued_offline"

    def _mark_printer_dead_nolock(self):
        if self._printer:
            try:
                self._printer.close()
            except Exception:
                pass
        self._printer = None

    def _enqueue_silent_ticket(
        self,
        ticket_code: str,
        qr_string: str,
        validity_hours: int,
        user_name: str,
        notes: Optional[str],
        reason: str
    ):
        """
        Guarda silenciosamente la orden en el archivo de auditoría local (JSONL) para que
        no bloquee la base de datos central de Supabase ni las peticiones entrantes.
        """
        try:
            record = {
                "ticket_code": ticket_code,
                "qr_string": qr_string,
                "validity_hours": validity_hours,
                "user_name": user_name,
                "notes": notes,
                "failed_at": datetime.now().isoformat(),
                "error_reason": reason
            }
            with open(FAILED_TICKETS_LOG_PATH, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
            logger.info(f"📂 [Log Sordo] Ticket '{ticket_code}' encolado en '{FAILED_TICKETS_LOG_PATH}'.")
        except Exception as log_err:
            logger.error(f"❌ [Log Sordo] No se pudo escribir en log local de fallas de impresora: {log_err}")

    def flush_offline_queue(self):
        """
        Intenta imprimir en segundo plano los tickets que se acumularon durante el fallo o falta de papel.
        """
        if not os.path.exists(FAILED_TICKETS_LOG_PATH):
            return

        with self._lock:
            if not self._printer:
                return

        try:
            with open(FAILED_TICKETS_LOG_PATH, "r", encoding="utf-8") as f:
                lines = [line.strip() for line in f if line.strip()]

            if not lines:
                return

            logger.info(f"🚀 [Cola Sorda] Purgando e imprimiendo {len(lines)} ticket(s) offline pendientes...")
            remaining_lines = []

            for line in lines:
                try:
                    payload = json.loads(line)
                    ticket_code = payload.get("ticket_code")
                    qr_string = payload.get("qr_string") or ticket_code
                    validity_hours = payload.get("validity_hours", 24)
                    user_name = payload.get("user_name", "Visita GymPro")
                    notes = payload.get("notes")

                    # Imprimir directamente (llamando con lock interno o control recursivo seguro)
                    success, status = self.print_daily_visit_ticket(
                        ticket_code=ticket_code,
                        qr_string=qr_string,
                        validity_hours=validity_hours,
                        user_name=f"{user_name} [RETRY]",
                        notes=notes
                    )
                    if status == "queued_offline":
                        remaining_lines.append(line)  # Aún falla
                except Exception:
                    remaining_lines.append(line)

            # Reescribir solo los que no se pudieron imprimir
            with open(FAILED_TICKETS_LOG_PATH, "w", encoding="utf-8") as f:
                for r_line in remaining_lines:
                    f.write(r_line + "\n")

            if not remaining_lines:
                logger.info("✅ [Cola Sorda] Todos los tickets pendientes se han impreso y el log ha quedado limpio.")
        except Exception as e:
            logger.error(f"❌ [Cola Sorda] Error al purgar cola local: {e}")

    def _simulate_console_print(self, code: str, qr: str, hours: int, name: str, notes: Optional[str], date_str: str):
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
        """Detiene el auto-healer y cierra la impresora al salir."""
        self._running = False
        with self._lock:
            if self._printer:
                try:
                    self._printer.close()
                except Exception:
                    pass
            self._printer = None
