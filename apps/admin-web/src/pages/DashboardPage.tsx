import { useMemo, useState } from 'react';
import { API } from '../lib/config';
import { http } from '../lib/api';
import { useAsync } from '../lib/useAsync';
import { useTheme } from '../lib/useTheme';
import { money } from '../lib/format';
import type { FinanceSummary } from '../lib/types';
import { Card, CardHeader } from '../components/ui/Card';
import { KPIStat } from '../components/ui/KPIStat';
import { StatusBadge } from '../components/ui/StatusBadge';
import { PillFilter } from '../components/ui/PillFilter';
import { RevenueAreaChart } from '../components/charts/RevenueAreaChart';
import { AltasBajasBarChart } from '../components/charts/AltasBajasBarChart';
import { RetentionDonut } from '../components/charts/RetentionDonut';
import { ingresosSeries, altasBajasSeries, lastDelta, type Period } from '../lib/financeSample';
import { FinanceIcon, UsersGroupIcon, AlertIcon, ArrowUpIcon, ArrowDownIcon } from '../components/icons';

const PERIODS: readonly Period[] = ['Mensual', 'Trimestral', 'Anual'];

/** Formato compacto para el eje Y de ingresos ($12.5k). */
const compact = (n: number) =>
  Math.abs(n) >= 1000 ? `$${(n / 1000).toFixed(n % 1000 === 0 ? 0 : 1)}k` : `$${n}`;

const tint = {
  indigo: 'bg-indigo-50 text-indigo-600 dark:bg-indigo-500/10 dark:text-indigo-400',
  green:  'bg-emerald-50 text-emerald-600 dark:bg-emerald-500/10 dark:text-emerald-400',
  amber:  'bg-amber-50 text-amber-600 dark:bg-amber-500/10 dark:text-amber-400',
  red:    'bg-red-50 text-red-500 dark:bg-red-500/10 dark:text-red-400',
};

export function DashboardPage() {
  const { theme } = useTheme();
  const dark = theme === 'dark';
  const [period, setPeriod] = useState<Period>('Mensual');

  // GET /admin/finance/summary (payment-service) — KPIs reales.
  const { data, loading, error } = useAsync<FinanceSummary>(
    () => http.get<FinanceSummary>(`${API.payment}/admin/finance/summary`),
  );

  // Series de MUESTRA derivadas del resumen (ver financeSample.ts).
  const ingresos = useMemo(
    () => ingresosSeries(data?.ingresosMes ?? 0, period),
    [data?.ingresosMes, period],
  );
  const altasBajas = useMemo(
    () => altasBajasSeries(data?.altasMes ?? 0, data?.bajasMes ?? 0),
    [data?.altasMes, data?.bajasMes],
  );
  const mrrDelta = useMemo(() => lastDelta(ingresos), [ingresos]);

  // Salud de cartera (dato REAL): activas / (activas + en mora).
  const retencion = useMemo(() => {
    if (!data) return 0;
    const den = data.suscripcionesActivas + data.suscripcionesPastDue;
    return den === 0 ? 0 : (data.suscripcionesActivas / den) * 100;
  }, [data]);

  const muestra = <StatusBadge tone="amber">datos de muestra</StatusBadge>;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Dashboard financiero</h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
          Ingresos, suscripciones y salud de cartera del gimnasio.
        </p>
      </div>

      {loading && <div className="text-gray-500 dark:text-gray-400">Cargando métricas…</div>}
      {error && (
        <Card className="border-amber-200 dark:border-amber-500/30">
          <div className="flex items-start gap-3 text-amber-700 dark:text-amber-400 text-sm">
            <AlertIcon className="shrink-0 mt-0.5" />
            <p>
              No se pudo cargar el resumen financiero ({error}). Verifica que
              <code className="mx-1 px-1 rounded bg-amber-50 dark:bg-amber-500/10">GET /admin/finance/summary</code>
              esté disponible en payment-service.
            </p>
          </div>
        </Card>
      )}

      {data && (
        <>
          {/* ── KPIs ─────────────────────────────────────────────────────── */}
          <div className="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-5">
            <KPIStat
              icon={<FinanceIcon />} iconTint={tint.indigo}
              label="Ingresos del mes (MRR)" value={money(data.ingresosMes, data.moneda)}
            />
            <KPIStat
              icon={<UsersGroupIcon />} iconTint={tint.green}
              label="Suscripciones activas" value={data.suscripcionesActivas.toLocaleString('es-MX')}
            />
            <KPIStat
              icon={<AlertIcon />} iconTint={tint.amber}
              label="En mora (past due)" value={data.suscripcionesPastDue.toLocaleString('es-MX')}
            />
            <KPIStat
              icon={<ArrowUpIcon />} iconTint={tint.green}
              label="Altas del mes" value={data.altasMes.toLocaleString('es-MX')}
            />
            <KPIStat
              icon={<ArrowDownIcon />} iconTint={tint.red}
              label="Bajas del mes" value={data.bajasMes.toLocaleString('es-MX')}
            />
          </div>

          {/* ── Ingresos (área) + Retención (dona) ───────────────────────── */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <Card className="lg:col-span-2">
              <CardHeader
                title="Ingresos recurrentes"
                subtitle="Evolución del MRR"
                action={<PillFilter options={PERIODS} value={period} onChange={setPeriod} />}
              />
              <div className="flex items-center gap-3 mb-2">
                <span className="text-2xl font-bold text-gray-900 dark:text-white">
                  {money(data.ingresosMes, data.moneda)}
                </span>
                <span className={`inline-flex items-center gap-1 text-xs font-semibold px-2 py-1 rounded-lg ${
                  mrrDelta >= 0
                    ? 'text-emerald-600 bg-emerald-50 dark:bg-emerald-500/10'
                    : 'text-red-500 bg-red-50 dark:bg-red-500/10'
                }`}>
                  {mrrDelta >= 0 ? <ArrowUpIcon /> : <ArrowDownIcon />}{Math.abs(mrrDelta)}%
                </span>
                {muestra}
              </div>
              <RevenueAreaChart data={ingresos} dark={dark} format={compact} />
            </Card>

            <Card>
              <CardHeader title="Salud de cartera" subtitle="Activas vs. en mora" />
              <RetentionDonut value={retencion} dark={dark} centerLabel="al día" />
              <div className="mt-4 flex justify-center gap-6 text-sm">
                <div className="text-center">
                  <div className="font-bold text-gray-900 dark:text-white">{data.suscripcionesActivas}</div>
                  <div className="text-xs text-gray-500 dark:text-gray-400">Activas</div>
                </div>
                <div className="text-center">
                  <div className="font-bold text-amber-600">{data.suscripcionesPastDue}</div>
                  <div className="text-xs text-gray-500 dark:text-gray-400">En mora</div>
                </div>
              </div>
            </Card>
          </div>

          {/* ── Altas vs Bajas (barras) ──────────────────────────────────── */}
          <Card>
            <CardHeader
              title="Altas vs. bajas"
              subtitle="Últimos 6 meses"
              action={muestra}
            />
            <AltasBajasBarChart data={altasBajas} dark={dark} />
          </Card>
        </>
      )}
    </div>
  );
}
