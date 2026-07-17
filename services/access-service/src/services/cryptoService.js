/**
 * @file services/access-service/src/services/cryptoService.js
 * @description Criptografía avanzada para generación y verificación de tokens QR con AES-256-GCM.
 *
 * ¿Por qué AES-256-GCM en lugar de AES-256-CBC o JWT?
 *   1. Integridad autenticada (Auth Tag): AES-GCM produce un tag de autenticación
 *      de 16 bytes que garantiza que ni un solo bit del texto cifrado ha sido
 *      manipulado. Si un atacante altera el timestamp o usuario_id en el payload,
 *      decipher.final() arroja un error criptográfico instantáneo.
 *   2. Privacidad y Opacidad: El torniquete no necesita comunicarse a internet
 *      para leer el payload si tiene la clave simétrica, pero ningún usuario
 *      puede ver su contenido en texto plano.
 *   3. Compacto para lectura QR ultra-rápida: Al empaquetarse todo en base64url
 *      sin cabeceras largas, el código QR tiene menor densidad (menos puntos),
 *      lo que permite que las cámaras del torniquete lo lean en < 50 milisegundos.
 *
 * Estructura binaria del Token QR cifrado (antes de base64url):
 *   +-----------+--------------------+-------------------------+--------------------+
 *   | Versión   | IV (Initialization)| Auth Tag                | Ciphertext (JSON   |
 *   | (1 byte)  | Vector) (12 bytes) | (GCM Tag) (16 bytes)    | encriptado)        |
 *   +-----------+--------------------+-------------------------+--------------------+
 *   Total overhead binario = 29 bytes.
 */

'use strict';

const crypto = require('crypto');
const env    = require('../config/environment');
const { createServiceLogger } = require('../../../../packages_shared/security/logger');

const logger = createServiceLogger('access-service:cryptoService');

const ALGORITHM       = 'aes-256-gcm';
const KEY_BUFFER      = Buffer.from(env.AES_ENCRYPTION_KEY, 'hex');
const IV_LENGTH       = 12; // Estándar NIST SP 800-38D para GCM
const AUTH_TAG_LENGTH = 16;
const VERSION_BYTE    = 0x01; // Versión 1 del formato criptográfico

/**
 * Genera un token QR encriptado con AES-256-GCM.
 *
 * @param {object} payload - Datos a encriptar
 * @param {string} payload.usuario_id - UUID del usuario
 * @param {number} payload.timestamp  - Unix timestamp (ms)
 * @param {string} payload.nonce      - Hash/Token único de un solo uso
 * @returns {string} String URL-safe Base64 para incrustar en el código QR
 */
function encryptQrPayload(payload) {
  try {
    const jsonString = JSON.stringify(payload);
    const iv         = crypto.randomBytes(IV_LENGTH);

    const cipher = crypto.createCipheriv(ALGORITHM, KEY_BUFFER, iv);
    
    let ciphertext = cipher.update(jsonString, 'utf8');
    ciphertext     = Buffer.concat([ciphertext, cipher.final()]);
    
    const authTag  = cipher.getAuthTag();

    // Empaquetar todo en un solo Buffer: [Version (1)] + [IV (12)] + [AuthTag (16)] + [Ciphertext]
    const combinedBuffer = Buffer.concat([
      Buffer.from([VERSION_BYTE]),
      iv,
      authTag,
      ciphertext,
    ]);

    // Convertir a base64url para que sea seguro y óptimo en códigos QR
    return combinedBuffer.toString('base64url');
  } catch (err) {
    logger.error('Error encriptando payload QR con AES-256-GCM', { error: err.message });
    throw new Error('Fallo al generar el cifrado de seguridad del código QR.');
  }
}

/**
 * Desencripta y verifica un token QR generado con AES-256-GCM.
 *
 * @param {string} tokenBase64Url - Token escaneado por el torniquete
 * @returns {object} Payload original decodificado { usuario_id, timestamp, nonce }
 * @throws {Error} Si el formato es inválido, o la autenticación criptográfica falla
 */
function decryptQrPayload(tokenBase64Url) {
  try {
    const combinedBuffer = Buffer.from(tokenBase64Url, 'base64url');

    // Verificar longitud mínima (1 + 12 + 16 + al menos 2 bytes de JSON cifrado = 31 bytes)
    if (combinedBuffer.length < (1 + IV_LENGTH + AUTH_TAG_LENGTH + 2)) {
      throw new Error('Token QR corrupto o incompleto (longitud insuficiente).');
    }

    const version = combinedBuffer[0];
    if (version !== VERSION_BYTE) {
      throw new Error(`Versión de token QR no soportada (${version}).`);
    }

    const ivStart         = 1;
    const authTagStart    = ivStart + IV_LENGTH;
    const ciphertextStart = authTagStart + AUTH_TAG_LENGTH;

    const iv         = combinedBuffer.subarray(ivStart, authTagStart);
    const authTag    = combinedBuffer.subarray(authTagStart, ciphertextStart);
    const ciphertext = combinedBuffer.subarray(ciphertextStart);

    const decipher = crypto.createDecipheriv(ALGORITHM, KEY_BUFFER, iv);
    decipher.setAuthTag(authTag);

    let decrypted = decipher.update(ciphertext, null, 'utf8');
    decrypted    += decipher.final('utf8'); // Lanza error si el AuthTag no coincide

    return JSON.parse(decrypted);
  } catch (err) {
    logger.warn('Fallo en verificación criptográfica de token QR', { error: err.message });
    throw new Error('Token QR inválido, manipulado o dañado.');
  }
}

/**
 * Genera un nonce (hash de un solo uso) criptográficamente seguro.
 * @returns {string} Hex de 32 caracteres
 */
function generateNonce() {
  return crypto.randomBytes(16).toString('hex');
}

module.exports = {
  encryptQrPayload,
  decryptQrPayload,
  generateNonce,
};
