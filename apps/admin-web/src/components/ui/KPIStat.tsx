import type { ReactNode } from 'react';
import { Card } from './Card';
import { ArrowUpIcon, ArrowDownIcon } from '../icons';

interface KPIStatProps {
  icon: ReactNode;
  label: string;
  value: string;
  /** Tendencia opcional: número con signo. Positivo → verde, negativo → rojo. */
  trend?: { value: number; suffix?: string; invertColors?: boolean };
  /** Color del contenedor del icono (por defecto neutro). */
  iconTint?: string;
}

/**
 * KPI card TailAdmin: icono en contenedor circular suave arriba, valor grande,
 * título debajo e indicador de tendencia con flecha y color semántico.
 */
export function KPIStat({ icon, label, value, trend, iconTint }: KPIStatProps) {
  const positive = trend ? trend.value >= 0 : true;
  // invertColors: para métricas donde "subir" es malo (mora, bajas).
  const good = trend?.invertColors ? !positive : positive;

  return (
    <Card>
      <div
        className={`w-11 h-11 rounded-full flex items-center justify-center ${
          iconTint ?? 'bg-gray-50 dark:bg-gray-700/50 text-gray-500 dark:text-gray-300'
        }`}
      >
        {icon}
      </div>

      <div className="mt-4 flex items-end justify-between">
        <div>
          <div className="text-3xl font-bold text-gray-900 dark:text-white tabular-nums">{value}</div>
          <div className="text-sm text-gray-500 dark:text-gray-400 mt-1">{label}</div>
        </div>

        {trend && (
          <span
            className={`inline-flex items-center gap-1 text-xs font-semibold px-2 py-1 rounded-lg ${
              good
                ? 'text-emerald-600 bg-emerald-50 dark:bg-emerald-500/10'
                : 'text-red-500 bg-red-50 dark:bg-red-500/10'
            }`}
          >
            {positive ? <ArrowUpIcon /> : <ArrowDownIcon />}
            {Math.abs(trend.value)}{trend.suffix ?? '%'}
          </span>
        )}
      </div>
    </Card>
  );
}
