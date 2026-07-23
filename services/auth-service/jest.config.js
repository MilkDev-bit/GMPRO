/**
 * @file jest.config.js
 * @description Configuración de Jest para este microservicio del monorepo GymPro.
 *
 * POR QUÉ modulePaths:
 *   Este servicio importa utilidades de `packages_shared/` (logger, jwtVerify,
 *   rateLimiter), que a su vez hacen `require("winston")`, `jsonwebtoken`, etc.
 *   Esos paquetes están en el node_modules de ESTE servicio, pero
 *   `packages_shared/` vive FUERA del servicio, así que la resolución de Node
 *   (que sube por el árbol desde el archivo que hace el require) no encuentra
 *   el node_modules del servicio: no es un directorio ancestro de packages_shared/.
 *
 *   En producción (Docker) funciona porque todo queda bajo /app con un único
 *   /app/node_modules que SÍ es ancestro de packages_shared/. En local no.
 *
 *   `modulePaths` añade la ruta absoluta del node_modules del servicio a la
 *   resolución GLOBAL de Jest, para que los módulos requeridos desde
 *   packages_shared/ se resuelvan contra este node_modules.
 */

"use strict";

module.exports = {
  testEnvironment: "node",
  modulePaths: ["<rootDir>/node_modules"],
  coveragePathIgnorePatterns: ["/node_modules/"],
  testPathIgnorePatterns: ["/node_modules/"],
};
