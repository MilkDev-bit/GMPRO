# 📟 Guía Rápida de Instalación y Despliegue en la PC de Recepción (GymPro)

El **Controlador de Hardware de Recepción (`services/reception-hardware-controller`)** está diseñado con doble motor (Python 3 y Node.js 20+) para garantizar compatibilidad absoluta con computadoras de mostrador bajo **Windows 10/11** o **Linux (Ubuntu/Debian)**.

---

## 🛠️ Opción A: Motor Python 3 (Recomendado para Linux y Windows)

### 1. Instalación de Dependencias
Abre una terminal (`cmd` o `bash`) en la carpeta `services/reception-hardware-controller/python/`:
```bash
# En Ubuntu / Debian (Instalar dependencias del sistema USB si es necesario):
sudo apt-get update && sudo apt-get install -y python3-pip python3-usb libusb-1.0-0

# Instalar librerías de Python:
pip3 install -r requirements.txt
```

### 2. Configuración de Puertos y Variables (`config.py` o `.env`)
Puedes editar directamente `config.py` o declarar variables de entorno:
* `QR_SERIAL_PORT`: `COM3` en Windows o `/dev/ttyACM0` en Linux.
* `RELAY_SERIAL_PORT`: `COM4` en Windows o `/dev/ttyUSB1` en Linux.
* `TURNSTILE_API_KEY`: Clave secreta que empareja con la variable en Railway (`TURNSTILE_API_KEY`).
* `RAILWAY_ACCESS_SERVICE_URL`: URL en la nube de tu `access-service` (ej. `https://access-service.gympro.railway.app/api/v1/access`).

### 3. Ejecutar el Controlador (Modo Demon/Servicio)
```bash
python3 main.py
```
> **Nota de Seguridad en Linux (`evdev HID Grab`)**: Si el lector QR opera por USB HID en lugar de puerto COM, el script en Linux ejecuta `device.grab()` para secuestrar los eventos del kernel. Esto requiere permisos `sudo python3 main.py` o agregar el usuario de recepción al grupo `input` (`sudo usermod -a -G input $USER`).

---

## 🟢 Opción B: Motor Node.js 20+ (Recomendado para Windows con Emulación COM)

### 1. Instalación
Abre una terminal en `services/reception-hardware-controller/node/`:
```bash
npm install
```

### 2. Ejecución
```bash
npm start
```
El script abrirá en modo `lock: true` el puerto serie del lector para que los escaneos del torniquete **jamás** interrumpan al recepcionista mientras navega en Chrome, Excel o el CRM del mostrador.

---

## 🌐 Pruebas Locales del Servidor de Impresión Térmica

Tanto en Python como en Node.js, el controlador levanta un servidor local ligero en `http://127.0.0.1:18999/print-ticket` que permite a la interfaz web de la recepción solicitar la impresión del ticket físico en papel de 80mm al momento en que un usuario compra un pase diario:

```bash
curl -X POST http://127.0.0.1:18999/print-ticket \
  -H "Content-Type: application/json" \
  -d '{
    "codigo_ticket": "GP-8F3A-9D1B-4E2C",
    "user_name": "Carlos Mendoza (Pase 1 Día)",
    "vigencia_horas": 24,
    "qr_string": "GP-8F3A-9D1B-4E2C",
    "notas": "Pago en efectivo en mostrador"
  }'
```
