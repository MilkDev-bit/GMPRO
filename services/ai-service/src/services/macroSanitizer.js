/**
 * @file services/ai-service/src/services/macroSanitizer.js
 * @description Validador/Sanitizador de consistencia termodinámica de los planes
 * nutricionales que genera la IA (Eje 3 de la auditoría).
 *
 * LEY DE ATWATER (energía por gramo):
 *   proteína = 4 kcal · carbohidrato = 4 kcal · grasa = 9 kcal
 *
 * La IA suele "redondear a ojo" y dejar que `calorias_meta` NO cuadre con la suma
 * energética de los macros, o que la suma de comidas no cuadre con la meta diaria.
 * Este módulo detecta y CORRIGE esas discrepancias ANTES de persistir en Supabase o
 * responder al frontend, evitando información contradictoria para el usuario.
 *
 * Principio de verdad: los GRAMOS de macronutriente mandan sobre las kcal declaradas
 * (la energía es una función determinista de los gramos). Por eso las kcal se
 * recalculan a partir de los gramos, no al revés.
 */

'use strict';

const ATWATER = Object.freeze({ protein: 4, carb: 4, fat: 9 });

/** Convierte a número finito o 0. */
function num(v) {
  const n = typeof v === 'string' ? parseFloat(v) : v;
  return Number.isFinite(n) ? n : 0;
}

/** Energía (kcal) a partir de gramos de macros. */
function kcalFromMacros(proteinG, carbG, fatG) {
  return ATWATER.protein * num(proteinG)
       + ATWATER.carb    * num(carbG)
       + ATWATER.fat     * num(fatG);
}

/** Diferencia relativa segura (evita división por cero). */
function relDiff(a, b) {
  const base = Math.max(Math.abs(a), Math.abs(b), 1);
  return Math.abs(a - b) / base;
}

/**
 * Valida y reconcilia la consistencia energética de un plan nutricional de la IA.
 *
 * @param {object} plan - JSON del plan (mutado in place con las correcciones).
 * @param {object} [opts]
 * @param {number} [opts.tolerance=0.03]      - Holgura relativa permitida (3%) antes de corregir.
 * @param {boolean} [opts.reconcileTotals=true] - Recalcular calorias_meta desde los macros meta.
 * @param {boolean} [opts.reconcileMeals=true]   - Recalcular kcal por comida desde sus macros.
 * @returns {{ plan: object, isConsistent: boolean, corrections: string[], warnings: string[] }}
 */
function validateAndReconcile(plan, opts = {}) {
  const {
    tolerance       = 0.03,
    reconcileTotals = true,
    reconcileMeals  = true,
  } = opts;

  const corrections = [];
  const warnings    = [];

  if (!plan || typeof plan !== 'object') {
    return { plan, isConsistent: false, corrections, warnings: ['Plan nulo o no-objeto.'] };
  }

  // ── 1. Meta diaria: calorias_meta vs energía de los macros meta ─────────────
  const metaKcalDeclared = num(plan.calorias_meta);
  const metaKcalDerived  = Math.round(
    kcalFromMacros(plan.proteinas_meta_g, plan.carbohidratos_meta_g, plan.grasas_meta_g)
  );

  if (metaKcalDerived > 0 && relDiff(metaKcalDeclared, metaKcalDerived) > tolerance) {
    if (reconcileTotals) {
      corrections.push(
        `calorias_meta ${metaKcalDeclared} → ${metaKcalDerived} (recalculado desde ${num(plan.proteinas_meta_g)}P/${num(plan.carbohidratos_meta_g)}C/${num(plan.grasas_meta_g)}G).`
      );
      plan.calorias_meta = metaKcalDerived;
    } else {
      warnings.push(`calorias_meta declarada (${metaKcalDeclared}) ≠ derivada (${metaKcalDerived}).`);
    }
  }

  // ── 2. Consistencia por comida ──────────────────────────────────────────────
  const meals = Array.isArray(plan.comidas) ? plan.comidas : [];
  let sumP = 0, sumC = 0, sumF = 0, sumKcal = 0;

  for (const meal of meals) {
    const mealKcalDerived = Math.round(kcalFromMacros(meal.proteinas, meal.carbohidratos, meal.grasas));
    const mealKcalDeclared = num(meal.calorias);

    if (mealKcalDerived > 0 && relDiff(mealKcalDeclared, mealKcalDerived) > tolerance) {
      if (reconcileMeals) {
        corrections.push(
          `comida "${meal.tipo || meal.id || meal.nombre || 's/n'}": calorias ${mealKcalDeclared} → ${mealKcalDerived}.`
        );
        meal.calorias = mealKcalDerived;
      } else {
        warnings.push(`comida "${meal.tipo || meal.id}" incoherente: ${mealKcalDeclared} vs ${mealKcalDerived}.`);
      }
    }

    sumP += num(meal.proteinas);
    sumC += num(meal.carbohidratos);
    sumF += num(meal.grasas);
    sumKcal += num(meal.calorias);

    // 2.b Consistencia intrínseca de cada alimento (por 100 g), con holgura mayor
    // por redondeo de fibra/polialcoholes en Open Food Facts.
    if (Array.isArray(meal.alimentos)) {
      for (const food of meal.alimentos) {
        const foodKcal = kcalFromMacros(food.proteinas_100g, food.carbohidratos_100g, food.grasas_100g);
        if (foodKcal > 0 && num(food.calorias_100g) > 0 && relDiff(num(food.calorias_100g), foodKcal) > 0.15) {
          warnings.push(
            `alimento "${food.nombre || food.codigo_barras}": calorias_100g ${num(food.calorias_100g)} ≠ ${Math.round(foodKcal)} (macros).`
          );
        }
      }
    }
  }

  // ── 3. La suma de comidas debe aproximarse a la meta diaria ─────────────────
  if (meals.length > 0) {
    const sumKcalFromMacros = Math.round(kcalFromMacros(sumP, sumC, sumF));
    const metaFinal = num(plan.calorias_meta);
    if (metaFinal > 0 && relDiff(sumKcalFromMacros, metaFinal) > Math.max(tolerance, 0.05)) {
      warnings.push(
        `La suma energética de las comidas (${sumKcalFromMacros} kcal / ${Math.round(sumP)}P·${Math.round(sumC)}C·${Math.round(sumF)}G) ` +
        `difiere de calorias_meta (${metaFinal}). Revisar reparto de comidas.`
      );
    }
    // Adjuntar totales calculados como metadato de confianza para el frontend.
    plan._macros_check = {
      suma_comidas_kcal:  sumKcal,
      suma_macros_kcal:   sumKcalFromMacros,
      proteinas_sumadas_g: Math.round(sumP),
      carbohidratos_sumados_g: Math.round(sumC),
      grasas_sumadas_g:   Math.round(sumF),
    };
  }

  return {
    plan,
    isConsistent: corrections.length === 0 && warnings.length === 0,
    corrections,
    warnings,
  };
}

module.exports = {
  ATWATER,
  kcalFromMacros,
  validateAndReconcile,
};
