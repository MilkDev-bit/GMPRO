/**
 * @file services/ai-service/src/constants/muscleGroups.js
 * @description Catálogo completo de grupos musculares según el estándar internacional de anatomía fitness.
 * Mapea cada músculo a su región corporal, vista (frontal/trasera) y coordenadas normalizadas en
 * el mapa anatómico SVG (x%, y% desde la esquina superior izquierda del lienzo de 200x400px).
 *
 * Nomenclatura compatible con:
 *   • wger Workout Manager API (international muscle IDs)
 *   • NSCA Exercise Terminology (National Strength & Conditioning Association)
 *   • ACSM Muscle Classification (American College of Sports Medicine)
 */

'use strict';

/**
 * Catálogo canónico de músculos para GymPro AI.
 * Cada clave es el ID usado en el JSON de rutinas.
 * La región 'anterior' = vista frontal; 'posterior' = vista trasera.
 */
const MUSCLE_CATALOG = {
  // ── PECTORALES ─────────────────────────────────────────────────────────────
  pectoral_mayor_superior:    { region: 'anterior', label: 'Pectoral Mayor (Clavicular)', color: '#FF007A' },
  pectoral_mayor_esternal:    { region: 'anterior', label: 'Pectoral Mayor (Esternal)',   color: '#FF007A' },
  pectoral_menor:             { region: 'anterior', label: 'Pectoral Menor',               color: '#FF4D9E' },

  // ── DELTOIDES ──────────────────────────────────────────────────────────────
  deltoides_anterior:         { region: 'anterior', label: 'Deltoides Anterior',           color: '#FF9500' },
  deltoides_lateral:          { region: 'anterior', label: 'Deltoides Lateral',            color: '#FF9500' },
  deltoides_posterior:        { region: 'posterior', label: 'Deltoides Posterior',         color: '#FF9500' },

  // ── ESPALDA ────────────────────────────────────────────────────────────────
  dorsal_ancho:               { region: 'posterior', label: 'Dorsal Ancho (Latissimus)',   color: '#00F0FF' },
  trapecio_superior:          { region: 'posterior', label: 'Trapecio Superior',           color: '#00D4E6' },
  trapecio_medio:             { region: 'posterior', label: 'Trapecio Medio',              color: '#00D4E6' },
  trapecio_inferior:          { region: 'posterior', label: 'Trapecio Inferior',           color: '#00D4E6' },
  romboides:                  { region: 'posterior', label: 'Romboides Mayor y Menor',     color: '#009EB0' },
  erector_espinal:            { region: 'posterior', label: 'Erector de la Columna',       color: '#0078A0' },
  redondo_mayor:              { region: 'posterior', label: 'Redondo Mayor (Teres Major)', color: '#0095C0' },
  redondo_menor:              { region: 'posterior', label: 'Redondo Menor (Teres Minor)', color: '#00A8D8' },

  // ── BÍCEPS / TRÍCEPS ───────────────────────────────────────────────────────
  biceps_braquial:            { region: 'anterior', label: 'Bíceps Braquial',              color: '#9D00FF' },
  braquial:                   { region: 'anterior', label: 'Braquial (Braquialis)',         color: '#B040FF' },
  braquiorradial:             { region: 'anterior', label: 'Braquiorradial',               color: '#C070FF' },
  triceps_braquial:           { region: 'posterior', label: 'Tríceps Braquial',            color: '#7A00CC' },
  triceps_largo:              { region: 'posterior', label: 'Tríceps (Cabeza Larga)',       color: '#8820DD' },

  // ── ANTEBRAZO ─────────────────────────────────────────────────────────────
  flexores_antebrazo:         { region: 'anterior', label: 'Flexores del Antebrazo',       color: '#D4A0FF' },
  extensores_antebrazo:       { region: 'posterior', label: 'Extensores del Antebrazo',   color: '#C090EE' },

  // ── CORE (ABDOMEN / OBLICUOS / LUMBAR) ────────────────────────────────────
  recto_abdominal:            { region: 'anterior', label: 'Recto Abdominal',              color: '#00E699' },
  oblicuo_externo:            { region: 'anterior', label: 'Oblicuo Externo',              color: '#00CC80' },
  oblicuo_interno:            { region: 'anterior', label: 'Oblicuo Interno',              color: '#00BB70' },
  transverso_abdominal:       { region: 'anterior', label: 'Transverso Abdominal',         color: '#009960' },
  cuadrado_lumbar:            { region: 'posterior', label: 'Cuadrado Lumbar',             color: '#007A50' },

  // ── GLÚTEOS ────────────────────────────────────────────────────────────────
  gluteo_mayor:               { region: 'posterior', label: 'Glúteo Mayor (Gluteus Max)',  color: '#FF007A' },
  gluteo_medio:               { region: 'posterior', label: 'Glúteo Medio',               color: '#FF4D9E' },
  gluteo_menor:               { region: 'posterior', label: 'Glúteo Menor',               color: '#FF80B0' },

  // ── CUÁDRICEPS ─────────────────────────────────────────────────────────────
  cuadriceps_recto:           { region: 'anterior', label: 'Recto Femoral',               color: '#FFB800' },
  cuadriceps_vasto_lateral:   { region: 'anterior', label: 'Vasto Lateral',               color: '#FFD040' },
  cuadriceps_vasto_medial:    { region: 'anterior', label: 'Vasto Medial',                color: '#FFE070' },
  cuadriceps_vasto_intermedio:{ region: 'anterior', label: 'Vasto Intermedio',            color: '#FFC020' },

  // ── ISQUIOTIBIALES ─────────────────────────────────────────────────────────
  biceps_femoral:             { region: 'posterior', label: 'Bíceps Femoral',             color: '#FF6B35' },
  semitendinoso:              { region: 'posterior', label: 'Semitendinoso',              color: '#FF8050' },
  semimembranoso:             { region: 'posterior', label: 'Semimembranoso',             color: '#FF9060' },

  // ── ADUCTORES / ABDUCTORES ─────────────────────────────────────────────────
  aductor_mayor:              { region: 'anterior', label: 'Aductor Mayor',               color: '#FF4080' },
  aductor_largo:              { region: 'anterior', label: 'Aductor Largo',               color: '#FF5090' },
  tensor_fascia_lata:         { region: 'anterior', label: 'Tensor de la Fascia Lata',    color: '#FF60A0' },

  // ── GEMELOS / SÓLEO / PIE ─────────────────────────────────────────────────
  gemelo_medial:              { region: 'posterior', label: 'Gastrocnemio Medial',        color: '#00BBFF' },
  gemelo_lateral:             { region: 'posterior', label: 'Gastrocnemio Lateral',       color: '#00CCFF' },
  soleo:                      { region: 'posterior', label: 'Sóleo',                      color: '#00DDFF' },
  tibial_anterior:            { region: 'anterior', label: 'Tibial Anterior',             color: '#40E0FF' },
};

/** Lista de todas las claves de músculos válidas para validación en prompts IA */
const VALID_MUSCLE_KEYS = Object.keys(MUSCLE_CATALOG);

/** Músculos que aparecen en vista frontal */
const ANTERIOR_MUSCLES = VALID_MUSCLE_KEYS.filter((k) => MUSCLE_CATALOG[k].region === 'anterior');

/** Músculos que aparecen en vista trasera */
const POSTERIOR_MUSCLES = VALID_MUSCLE_KEYS.filter((k) => MUSCLE_CATALOG[k].region === 'posterior');

module.exports = {
  MUSCLE_CATALOG,
  VALID_MUSCLE_KEYS,
  ANTERIOR_MUSCLES,
  POSTERIOR_MUSCLES,
};
