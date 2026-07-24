// Series de MUESTRA para los gráficos del dashboard financiero.
//
// El backend hoy expone GET /admin/finance/summary (escalares reales), pero aún
// NO una serie temporal de ingresos. Para no bloquear la UI, estos helpers
// sintetizan una serie representativa a partir del resumen real; las tarjetas de
// gráfico lo marcan visiblemente como "muestra". Cuando exista el endpoint
// GET /admin/finance/series, basta con sustituir estas funciones por el fetch.

export type Period = 'Mensual' | 'Trimestral' | 'Anual';
export interface RangePoint { label: string; value: number; }
export interface AltaBaja { label: string; altas: number; bajas: number; }

const MESES = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

/** 36 meses terminando en el mes actual, con tendencia suave hacia `target`. */
function base36(target: number): { y: number; m: number; value: number }[] {
  const now = new Date();
  const pts: { y: number; m: number; value: number }[] = [];
  for (let i = 35; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const t = (35 - i) / 35;                                   // 0..1
    const growth = 0.55 + 0.45 * t;                            // crece con el tiempo
    const season = 1 + 0.06 * Math.sin((d.getMonth() / 12) * Math.PI * 2);
    pts.push({ y: d.getFullYear(), m: d.getMonth(), value: Math.round(target * growth * season) });
  }
  return pts;
}

/** Serie de ingresos según el periodo seleccionado (pill Mensual/Trimestral/Anual). */
export function ingresosSeries(target: number, period: Period): RangePoint[] {
  const b = base36(target || 1);

  if (period === 'Mensual') {
    return b.slice(-12).map((p) => ({ label: MESES[p.m], value: p.value }));
  }

  if (period === 'Trimestral') {
    const last24 = b.slice(-24);
    const out: RangePoint[] = [];
    for (let i = 0; i < last24.length; i += 3) {
      const chunk = last24.slice(i, i + 3);
      const sum = chunk.reduce((a, c) => a + c.value, 0);
      const q = Math.floor(chunk[0].m / 3) + 1;
      out.push({ label: `T${q} '${String(chunk[0].y).slice(2)}`, value: sum });
    }
    return out;
  }

  // Anual: suma por año (3 años)
  const byYear = new Map<number, number>();
  for (const p of b) byYear.set(p.y, (byYear.get(p.y) ?? 0) + p.value);
  return [...byYear.entries()].map(([y, value]) => ({ label: String(y), value }));
}

/** Últimos 6 meses de altas vs bajas; el mes actual usa los valores reales. */
export function altasBajasSeries(altas: number, bajas: number): AltaBaja[] {
  const now = new Date();
  const wob = (n: number, k: number, i: number) =>
    Math.max(0, Math.round(n * (0.7 + 0.35 * Math.abs(Math.sin(i + k)))));
  const out: AltaBaja[] = [];
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    out.push({
      label: MESES[d.getMonth()],
      altas: i === 0 ? altas : wob(altas, 1, i),
      bajas: i === 0 ? bajas : wob(bajas, 2, i),
    });
  }
  return out;
}

/** Variación % del último punto respecto al anterior (para el chip de tendencia). */
export function lastDelta(series: RangePoint[]): number {
  if (series.length < 2) return 0;
  const a = series[series.length - 2].value;
  const b = series[series.length - 1].value;
  if (a === 0) return 0;
  return Math.round(((b - a) / a) * 1000) / 10;
}
