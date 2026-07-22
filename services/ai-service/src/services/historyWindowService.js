/**
 * @file services/ai-service/src/services/historyWindowService.js
 * @description Ventana móvil del historial de conversación.
 *
 * POR QUÉ ES NECESARIO AQUÍ:
 *   En este servicio el historial lo envía el CLIENTE en `req.body.history`.
 *   Sin recorte server-side, una app con un bug (o un cliente malicioso)
 *   puede mandar 500 turnos y los pagamos íntegros en tokens de entrada.
 *   Por eso esto no es solo una optimización de coste: es un límite duro
 *   que el backend debe imponer y no puede delegar en el cliente.
 *
 * QUÉ HACE:
 *   Conserva los últimos N pares (usuario + modelo) y aplica además un
 *   techo de caracteres, porque N pares no acota nada si un solo turno
 *   trae 3000 palabras pegadas.
 *
 * INVARIANTES (romperlos hace que Gemini devuelva 400):
 *   1. El historial debe EMPEZAR con un turno de usuario.
 *   2. No debe TERMINAR con un turno de usuario: el mensaje nuevo va
 *      justo después y dos turnos 'user' seguidos confunden al modelo.
 */

'use strict';

const DEFAULT_PAIRS = parseInt(process.env.AI_HISTORY_PAIRS || '4', 10);
const DEFAULT_MAX_CHARS = parseInt(process.env.AI_HISTORY_MAX_CHARS || '6000', 10);

/**
 * Normaliza el rol a 'user' | 'assistant'.
 *
 * ⚠ Se emite 'assistant' (NO 'model') a propósito: llmClientService hace
 * `msg.role === 'assistant' ? 'model' : 'user'`, así que un turno con
 * rol 'model' se convertiría en 'user' y la conversación quedaría con
 * todos los turnos del mismo lado. Este módulo devuelve exactamente la
 * forma que ese servicio ya espera: { role, content }.
 */
function normalizeRole(role) {
  const r = String(role || '').toLowerCase();
  return r === 'model' || r === 'assistant' ? 'assistant' : 'user';
}

/** Extrae el texto de un turno, admitiendo varias formas de entrada. */
function extractText(turn) {
  if (typeof turn === 'string') return turn;
  if (typeof turn?.content === 'string') return turn.content;
  if (typeof turn?.text === 'string') return turn.text;
  if (Array.isArray(turn?.parts)) {
    return turn.parts.map((p) => p?.text ?? '').join(' ');
  }
  return '';
}

function sizeOf(turn) {
  return turn.content.length;
}

/**
 * Aplica la ventana móvil.
 *
 * @param {Array} history - historial crudo recibido del cliente
 * @param {object} [opts]
 * @param {number} [opts.pairs]     pares usuario+modelo a conservar
 * @param {number} [opts.maxChars]  techo de caracteres total
 * @returns {{ turns: Array<{role:'user'|'assistant',content:string}>, stats: object }}
 */
function applyWindow(history, { pairs = DEFAULT_PAIRS, maxChars = DEFAULT_MAX_CHARS } = {}) {
  if (!Array.isArray(history) || history.length === 0) {
    return { turns: [], stats: { received: 0, kept: 0, droppedTurns: 0, charsBefore: 0, charsAfter: 0 } };
  }

  // Se emite { role, content }: la forma exacta que ya consume
  // llmClientService. Usar otro nombre de campo (p. ej. `text`) haría
  // que `msg.content || ''` enviara mensajes VACÍOS sin ningún error.
  const normalized = history
    .map((t) => ({ role: normalizeRole(t?.role), content: extractText(t).trim() }))
    .filter((t) => t.content.length > 0);

  const charsBefore = normalized.reduce((a, t) => a + t.content.length, 0);

  // 1. Últimos N pares.
  let win = normalized.slice(-pairs * 2);

  // 2. Invariante: empezar en 'user'.
  while (win.length > 0 && win[0].role !== 'user') win = win.slice(1);

  // 3. Invariante: no terminar en 'user'.
  while (win.length > 0 && win[win.length - 1].role === 'user') win = win.slice(0, -1);

  // 4. Techo de caracteres: se descartan los turnos más antiguos de dos
  //    en dos para preservar la paridad usuario/modelo.
  let total = win.reduce((a, t) => a + sizeOf(t), 0);
  while (total > maxChars && win.length > 2) {
    total -= sizeOf(win[0]) + sizeOf(win[1]);
    win = win.slice(2);
  }
  while (win.length > 0 && win[0].role !== 'user') win = win.slice(1);

  const charsAfter = win.reduce((a, t) => a + t.content.length, 0);

  return {
    turns: win,
    stats: {
      received: history.length,
      kept: win.length,
      droppedTurns: history.length - win.length,
      charsBefore,
      charsAfter,
      // ~4 caracteres por token en español: suficiente para vigilar la
      // tendencia sin gastar una llamada a countTokens.
      estTokensSaved: Math.max(0, Math.round((charsBefore - charsAfter) / 4)),
    },
  };
}

module.exports = {
  applyWindow,
  DEFAULT_PAIRS,
  DEFAULT_MAX_CHARS,
};
