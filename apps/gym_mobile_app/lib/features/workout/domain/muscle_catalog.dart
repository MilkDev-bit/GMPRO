/// @file lib/features/workout/domain/muscle_catalog.dart
/// @description Catálogo canónico de músculos en Flutter, espejo del catálogo del ai-service.
/// Mapea cada clave a su región corporal, color neón y polígonos SVG de renderizado en el mapa anatómico.

import 'package:flutter/material.dart';

enum BodyRegion { anterior, posterior }

/// Descriptor de cada grupo muscular para visualización.
class MuscleDescriptor {
  const MuscleDescriptor({
    required this.key,
    required this.label,
    required this.region,
    required this.color,
    required this.svgPathId,
  });

  /// Clave canónica (debe coincidir con el ai-service)
  final String key;

  /// Nombre legible en español
  final String label;

  /// Vista corporal donde aparece este músculo
  final BodyRegion region;

  /// Color neón para la iluminación en el mapa
  final Color color;

  /// ID del elemento <path> en el SVG anatómico
  final String svgPathId;
}

/// Catálogo completo de músculos — 1:1 con `muscleGroups.js`
class MuscleCatalog {
  MuscleCatalog._();

  static const List<MuscleDescriptor> all = [
    // ── PECTORALES ────────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'pectoral_mayor_superior',     label: 'Pectoral Mayor (Clavicular)', region: BodyRegion.anterior, color: Color(0xFFB85182), svgPathId: 'pectoral_mayor_superior'),
    MuscleDescriptor(key: 'pectoral_mayor_esternal',     label: 'Pectoral Mayor (Esternal)',   region: BodyRegion.anterior, color: Color(0xFFB85182), svgPathId: 'pectoral_mayor_esternal'),
    MuscleDescriptor(key: 'pectoral_menor',              label: 'Pectoral Menor',              region: BodyRegion.anterior, color: Color(0xFFCB81A3), svgPathId: 'pectoral_menor'),

    // ── DELTOIDES ─────────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'deltoides_anterior',          label: 'Deltoides Anterior',          region: BodyRegion.anterior, color: Color(0xFFB88D51), svgPathId: 'deltoides_anterior'),
    MuscleDescriptor(key: 'deltoides_lateral',           label: 'Deltoides Lateral',           region: BodyRegion.anterior, color: Color(0xFFB88D51), svgPathId: 'deltoides_lateral'),
    MuscleDescriptor(key: 'deltoides_posterior',         label: 'Deltoides Posterior',         region: BodyRegion.posterior, color: Color(0xFFB88D51), svgPathId: 'deltoides_posterior'),

    // ── ESPALDA ───────────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'dorsal_ancho',                label: 'Dorsal Ancho (Latissimus)',   region: BodyRegion.posterior, color: Color(0xFF51B2B8), svgPathId: 'dorsal_ancho'),
    MuscleDescriptor(key: 'trapecio_superior',           label: 'Trapecio Superior',           region: BodyRegion.posterior, color: Color(0xFF51B0B8), svgPathId: 'trapecio_superior'),
    MuscleDescriptor(key: 'trapecio_medio',              label: 'Trapecio Medio',              region: BodyRegion.posterior, color: Color(0xFF51B0B8), svgPathId: 'trapecio_medio'),
    MuscleDescriptor(key: 'trapecio_inferior',           label: 'Trapecio Inferior',           region: BodyRegion.posterior, color: Color(0xFF51B0B8), svgPathId: 'trapecio_inferior'),
    MuscleDescriptor(key: 'romboides',                   label: 'Romboides',                   region: BodyRegion.posterior, color: Color(0xFF51ADB8), svgPathId: 'romboides'),
    MuscleDescriptor(key: 'erector_espinal',             label: 'Erector de la Columna',       region: BodyRegion.posterior, color: Color(0xFF519EB8), svgPathId: 'erector_espinal'),
    MuscleDescriptor(key: 'redondo_mayor',               label: 'Redondo Mayor',               region: BodyRegion.posterior, color: Color(0xFF51A1B8), svgPathId: 'redondo_mayor'),

    // ── BÍCEPS / TRÍCEPS ──────────────────────────────────────────────────────
    MuscleDescriptor(key: 'biceps_braquial',             label: 'Bíceps Braquial',             region: BodyRegion.anterior, color: Color(0xFF9051B8), svgPathId: 'biceps_braquial'),
    MuscleDescriptor(key: 'braquial',                    label: 'Braquial',                    region: BodyRegion.anterior, color: Color(0xFFA677C8), svgPathId: 'braquial'),
    MuscleDescriptor(key: 'triceps_braquial',            label: 'Tríceps Braquial',            region: BodyRegion.posterior, color: Color(0xFF8F51B8), svgPathId: 'triceps_braquial'),

    // ── CORE ──────────────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'recto_abdominal',             label: 'Recto Abdominal',             region: BodyRegion.anterior, color: Color(0xFF51B896), svgPathId: 'recto_abdominal'),
    MuscleDescriptor(key: 'oblicuo_externo',             label: 'Oblicuo Externo',             region: BodyRegion.anterior, color: Color(0xFF51B892), svgPathId: 'oblicuo_externo'),
    MuscleDescriptor(key: 'oblicuo_interno',             label: 'Oblicuo Interno',             region: BodyRegion.anterior, color: Color(0xFF51B88F), svgPathId: 'oblicuo_interno'),
    MuscleDescriptor(key: 'cuadrado_lumbar',             label: 'Cuadrado Lumbar',             region: BodyRegion.posterior, color: Color(0xFF51B895), svgPathId: 'cuadrado_lumbar'),

    // ── GLÚTEOS ───────────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'gluteo_mayor',                label: 'Glúteo Mayor',                region: BodyRegion.posterior, color: Color(0xFFB85182), svgPathId: 'gluteo_mayor'),
    MuscleDescriptor(key: 'gluteo_medio',                label: 'Glúteo Medio',                region: BodyRegion.posterior, color: Color(0xFFCB81A3), svgPathId: 'gluteo_medio'),

    // ── CUÁDRICEPS ────────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'cuadriceps_recto',            label: 'Recto Femoral',               region: BodyRegion.anterior, color: Color(0xFFB89B51), svgPathId: 'cuadriceps_recto'),
    MuscleDescriptor(key: 'cuadriceps_vasto_lateral',    label: 'Vasto Lateral',               region: BodyRegion.anterior, color: Color(0xFFC8B477), svgPathId: 'cuadriceps_vasto_lateral'),
    MuscleDescriptor(key: 'cuadriceps_vasto_medial',     label: 'Vasto Medial',                region: BodyRegion.anterior, color: Color(0xFFCDBD84), svgPathId: 'cuadriceps_vasto_medial'),

    // ── ISQUIOTIBIALES ────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'biceps_femoral',              label: 'Bíceps Femoral',              region: BodyRegion.posterior, color: Color(0xFFC48670), svgPathId: 'biceps_femoral'),
    MuscleDescriptor(key: 'semitendinoso',               label: 'Semitendinoso',               region: BodyRegion.posterior, color: Color(0xFFCC9783), svgPathId: 'semitendinoso'),

    // ── GEMELOS ───────────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'gemelo_medial',               label: 'Gastrocnemio Medial',         region: BodyRegion.posterior, color: Color(0xFF519DB8), svgPathId: 'gemelo_medial'),
    MuscleDescriptor(key: 'gemelo_lateral',              label: 'Gastrocnemio Lateral',        region: BodyRegion.posterior, color: Color(0xFF51A3B8), svgPathId: 'gemelo_lateral'),
    MuscleDescriptor(key: 'tibial_anterior',             label: 'Tibial Anterior',             region: BodyRegion.anterior, color: Color(0xFF77BBC8), svgPathId: 'tibial_anterior'),
    MuscleDescriptor(key: 'soleo',                       label: 'Sóleo',                       region: BodyRegion.posterior, color: Color(0xFF51AAB8), svgPathId: 'soleo'),

    // ── ANTEBRAZO ─────────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'flexores_antebrazo',          label: 'Flexores del Antebrazo',      region: BodyRegion.anterior, color: Color(0xFFAC84CD), svgPathId: 'flexores_antebrazo'),
    MuscleDescriptor(key: 'extensores_antebrazo',        label: 'Extensores del Antebrazo',    region: BodyRegion.posterior, color: Color(0xFFA984CD), svgPathId: 'extensores_antebrazo'),
    MuscleDescriptor(key: 'braquiorradial',              label: 'Braquiorradial',              region: BodyRegion.anterior, color: Color(0xFFAD84CD), svgPathId: 'braquiorradial'),

    // ── ADUCTORES ─────────────────────────────────────────────────────────────
    MuscleDescriptor(key: 'aductor_mayor',               label: 'Aductor Mayor',               region: BodyRegion.anterior, color: Color(0xFFC87792), svgPathId: 'aductor_mayor'),
    MuscleDescriptor(key: 'tensor_fascia_lata',          label: 'Tensor de la Fascia Lata',    region: BodyRegion.anterior, color: Color(0xFFCD84A1), svgPathId: 'tensor_fascia_lata'),
  ];

  /// Lookup rápido por clave
  static final Map<String, MuscleDescriptor> _byKey = {
    for (final m in all) m.key: m,
  };

  static MuscleDescriptor? byKey(String key) => _byKey[key];

  /// Todos los músculos de una región
  static List<MuscleDescriptor> ofRegion(BodyRegion region) =>
      all.where((m) => m.region == region).toList();
}
