// Consumo de GET /admin/finance/series (payment-service) + agregación por periodo.
// La serie llega mensual; el pill Mensual/Trimestral/Anual agrega en cliente.

import type { Period, RangePoint, AltaBaja } from './financeSample';

export interface MonthIngreso { ym: string; label: string; value: number; }
export interface MonthAltaBaja { ym: string; label: string; altas: number; bajas: number; }
export interface FinanceSeriesDTO {
  moneda: string;
  ingresos: MonthIngreso[];
  altasBajas: MonthAltaBaja[];
}

const MES = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
const monthOf = (ym: string) => Number(ym.split('-')[1]); // 1..12
const yearOf = (ym: string) => Number(ym.split('-')[0]);

/** Agrega la serie mensual de ingresos al periodo seleccionado. */
export function aggregateIngresos(monthly: MonthIngreso[], period: Period): RangePoint[] {
  if (period === 'Mensual') {
    return monthly.slice(-12).map((m) => ({ label: MES[monthOf(m.ym) - 1], value: m.value }));
  }

  if (period === 'Trimestral') {
    const last24 = monthly.slice(-24);
    const buckets = new Map<string, number>(); // clave "YYYY-Q#"
    for (const m of last24) {
      const q = Math.floor((monthOf(m.ym) - 1) / 3) + 1;
      const key = `${yearOf(m.ym)}-Q${q}`;
      buckets.set(key, (buckets.get(key) ?? 0) + m.value);
    }
    return [...buckets.entries()].map(([key, value]) => {
      const [y, q] = key.split('-Q');
      return { label: `T${q} '${y.slice(2)}`, value };
    });
  }

  // Anual
  const byYear = new Map<number, number>();
  for (const m of monthly) byYear.set(yearOf(m.ym), (byYear.get(yearOf(m.ym)) ?? 0) + m.value);
  return [...byYear.entries()].map(([y, value]) => ({ label: String(y), value }));
}

/** Últimos 6 meses de altas vs bajas (para el gráfico de barras). */
export function lastAltasBajas(monthly: MonthAltaBaja[]): AltaBaja[] {
  return monthly.slice(-6).map((m) => ({
    label: MES[monthOf(m.ym) - 1],
    altas: m.altas,
    bajas: m.bajas,
  }));
}
