/**
 * @file services/access-service/jest.config.js
 * @description Configuración de Jest para access-service.
 *
 * POR QUÉ modulePaths:
 *   Este servicio importa utilidades de `packages_shared/` (logger, jwtVerify,
 *   rateLimiter), que a su vez hacen `require('winston')`, `jsonwebtoken`, etc.
 *   Esos paquetes están en el node_modules de ESTE servicio, pero
 *   `packages_shared/` vive FUERA del servicio, así que la resolución de Node
 *   (que sube por el árbol desde el archivo que hace el require) no encuentra
 *   el node_modules del servicio: no es un directorio ancestro de
 *   packages_shared/.
 *
 *   En producción (Docker) funciona porque todo queda bajo /app con un único
 *   /app/node_modules que SÍ es ancestro de packages_shared/. En local no.
 *
 *   `modulePaths` añade la ruta absoluta del node_modules del servicio a la
 *   resolución GLOBAL de Jest, de modo que winston/jsonwebtoken/etc. se
 *   resuelvan también desde archivos de packages_shared/.
 */

'use strict';

module.exports = {
  testEnvironment: 'node',
  // Clave del fix: winston/jsonwebtoken/etc. requeridos desde packages_shared/
  // se resuelven contra el node_modules de ESTE servicio.
  modulePaths: ['<rootDir>/node_modules'],
  coveragePathIgnorePatterns: ['/node_modules/'],
  testPathIgnorePatterns: ['/node_modules/'],
};
