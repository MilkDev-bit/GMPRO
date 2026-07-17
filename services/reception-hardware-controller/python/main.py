#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@file services/reception-hardware-controller/python/main.py
@description Orquestador Principal del Hardware de Recepción (GymPro AI).
Ejecuta de forma continua:
  1. Captura exclusiva de códigos desde el Lector QR Omnidireccional en segundo plano.
  2. Validación segura contra el microservicio access-service en Railway via HTTP POST.
  3. Activación temporizada (1s) del Relevador USB para apertura del torniquete ZKTeco TS1000 Plus.
  4. Servidor local HTTP ligero (puerro 18999) para recibir solicitudes de impresión de tickets de visita.
"""

import os
import sys
import time
import json
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

import config
from access_api_client import RailwayAccessApiClient
from relay_controller import TurnstileRelayController
from thermal_printer import ThermalPrinterController
from qr_scanner_listener import QrScannerListener

# ── CONFIGURACIÓN DE LOGGING PROFESIONAL ─────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("HardwareController.Main")

# Instancias globales de controladores
api_client = RailwayAccessApiClient()
relay_controller = TurnstileRelayController()
printer_controller = ThermalPrinterController()


def on_qr_scanned(raw_code: str):
    """
    Handler principal disparado cada vez que el lector QR omnidireccional lee un código:
    • Envía el código al backend en Railway.
    • Si acceso_concedido == True, activa el relevador por 1 segundo para destrabar el ZKTeco TS1000.
    • Si es rechazado, emite advertencia acústica/visual en logs.
    """
    code = raw_code.strip()
    if not code:
        return

    logger.info(f"\n╔══════════════════════════════════════════════════════════════════════════════╗")
    logger.info(f"║ 📲 NUEVO CÓDIGO INTERCEPTADO -> '{code[:32]}...'")
    logger.info(f"╚══════════════════════════════════════════════════════════════════════════════╝")

    # 1. Validar contra el servidor de accesos en Railway
    acceso_concedido, data, mensaje = api_client.validate_scanned_code(code)

    if acceso_concedido:
        logger.info(f"🎉 [ACCESO AUTORIZADO] -> {mensaje}")
        # 2. Enviar señal de pulso al relevador USB (1 segundo por defecto según Tarea 5.1)
        unlocked = relay_controller.trigger_unlock_pulse(duration_seconds=config.PULSE_DURATION_SECONDS)
        if unlocked:
            logger.info("🟢 [TORNIQUETE LIBERADO] El usuario ha pasado por el torniquete ZKTeco TS1000 Plus.")
        else:
            logger.error("❌ [TORNIQUETE ERROR] El servidor concedió acceso pero el relevador físico falló.")
    else:
        logger.warning(f"🛑 [ACCESO DENEGADO] -> {mensaje}")
        # Aquí se podría activar un zumbador/buzzer USB opcional indicando rechazo al socio


# ── SERVIDOR HTTP LOCAL PARA IMPRESIÓN DE TICKETS TÉRMICOS ───────────────────
class LocalPrinterHandler(BaseHTTPRequestHandler):
    """
    Handler HTTP ligero para que la interfaz web o app del mostrador pueda solicitar
    la impresión de un ticket térmico de 80mm de forma local sin latencia del sistema central.
    POST http://localhost:18999/print-ticket
    """
    def do_POST(self):
        if self.path in ("/print-ticket", "/api/print-ticket"):
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length)
                payload = json.loads(body.decode("utf-8"))

                ticket_code = payload.get("codigo_ticket") or payload.get("ticket_code", "GP-TEST-0000")
                qr_string = payload.get("qr_string") or ticket_code
                validity_hours = int(payload.get("vigencia_horas", 24))
                user_name = payload.get("user_name") or payload.get("nombre", "Visita GymPro")
                notes = payload.get("notas", None)

                logger.info(f"🖨️ [Servidor HTTP Local] Recibida orden de impresión para ticket '{ticket_code}'")
                success, status = printer_controller.print_daily_visit_ticket(
                    ticket_code=ticket_code,
                    qr_string=qr_string,
                    validity_hours=validity_hours,
                    user_name=user_name,
                    notes=notes
                )

                # Siempre respondemos 200/202 para NO BLOQUEAR la base de datos ni el servidor central
                self.send_response(200 if success else 500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                
                msg = "Ticket impreso en papel de 80mm." if status == "printed" else (
                    "Impresora temporalmente offline/sin papel. Ticket encolado localmente en auditoría sorda." if status == "queued_offline" else "Impresión en consola/simulación."
                )
                self.wfile.write(json.dumps({
                    "success": success,
                    "print_status": status,
                    "mensaje": msg
                }).encode("utf-8"))
            except Exception as e:
                logger.error(f"❌ [Servidor HTTP Local] Error procesando solicitud de impresión: {e}")
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suprimir logs ruidosos en stdout
        pass


def start_local_printer_server(port: int = 18999):
    """Ejecuta el servidor HTTP local en un hilo daemon."""
    try:
        server = HTTPServer(("127.0.0.1", port), LocalPrinterHandler)
        logger.info(f"🌐 [Servidor Local] Escuchando órdenes de impresión térmica en http://127.0.0.1:{port}/print-ticket")
        server.serve_forever()
    except Exception as e:
        logger.error(f"❌ [Servidor Local] No se pudo iniciar el servidor HTTP de impresión: {e}")


# ── PUNTO DE ENTRADA PRINCIPAL ───────────────────────────────────────────────
def main():
    logger.info("=" * 80)
    logger.info("   🚀 GYMPRO AI — CONTROLADOR LOCAL DE RECEPCIÓN Y HARDWARE (Python 3)")
    logger.info("=" * 80)
    logger.info(f"• Servidor Railway : {config.RAILWAY_ACCESS_SERVICE_URL}")
    logger.info(f"• ID Torniquete    : {config.TURNSTILE_ID}")
    logger.info(f"• Lector QR Modo   : {config.QR_READER_MODE.upper()}")
    logger.info(f"• Relevador USB    : {config.RELAY_TYPE.upper()} en {config.RELAY_SERIAL_PORT}")
    logger.info(f"• Impresora 80mm   : {config.PRINTER_MODE.upper()}")
    logger.info("-" * 80)

    # 1. Iniciar el relevador USB del torniquete ZKTeco TS1000 Plus (con Auto-Healing cada 3s)
    relay_controller.start()

    # 2. Iniciar la impresora térmica de 80mm ESC/POS (con Auto-Healing y Cola Sorda)
    printer_controller.start()

    # 3. Iniciar el servidor local HTTP en segundo plano para recibir órdenes de impresión
    http_thread = threading.Thread(target=start_local_printer_server, args=(18999,), daemon=True, name="HttpPrinterServer")
    http_thread.start()

    # 4. Iniciar el interceptor y capturador exclusivo del lector QR omnidireccional
    qr_listener = QrScannerListener(on_code_scanned_callback=on_qr_scanned)
    if not qr_listener.start():
        logger.error("❌ Falló la inicialización del Lector QR. Saliendo del controlador...")
        sys.exit(1)

    logger.info("\n✅ [SISTEMA LISTO] El mostrador de recepción y torniquete están operando en tiempo real.")
    logger.info("   -> Escanee un código QR móvil o ticket impreso en el lector para probar.")
    logger.info("   -> Presione Ctrl+C en cualquier momento para apagar el servicio y asegurar el torniquete.\n")

    try:
        while True:
            time.sleep(1.0)
    except KeyboardInterrupt:
        logger.info("\n⚠️ [INTERRUPCIÓN] Apagando el controlador de hardware en el mostrador...")
    finally:
        qr_listener.stop()
        relay_controller.close()
        printer_controller.close()
        logger.info("🔒 [SISTEMA APAGADO] Todos los puertos liberados y torniquete ZKTeco asegurado.")


if __name__ == "__main__":
    main()
