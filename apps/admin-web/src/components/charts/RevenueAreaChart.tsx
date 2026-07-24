import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

export interface SeriesPoint { label: string; value: number; }

interface Props {
  data: SeriesPoint[];
  dark?: boolean;
  /** Formatea el valor (eje Y y tooltip). */
  format?: (n: number) => string;
  height?: number;
}

const AXIS = '#94a3b8';

/**
 * Gráfico de área de ingresos (MRR). Curva monotone, gradiente vertical
 * morado→transparente, sin grid vertical y grid horizontal punteado tenue.
 */
export function RevenueAreaChart({ data, dark, format = (n) => String(n), height = 300 }: Props) {
  const grid = dark ? '#334155' : '#eef2f7';
  return (
    <ResponsiveContainer width="100%" height={height}>
      <AreaChart data={data} margin={{ top: 10, right: 8, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id="mrrFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#7C3AED" stopOpacity={0.35} />
            <stop offset="100%" stopColor="#7C3AED" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid vertical={false} strokeDasharray="4 4" stroke={grid} />
        <XAxis dataKey="label" tickLine={false} axisLine={false} tick={{ fill: AXIS, fontSize: 12 }} dy={8} />
        <YAxis
          tickLine={false} axisLine={false} width={48}
          tick={{ fill: AXIS, fontSize: 12 }} tickFormatter={format}
        />
        <Tooltip
          cursor={{ stroke: '#7C3AED', strokeWidth: 1, strokeDasharray: '4 4' }}
          contentStyle={{
            borderRadius: 12, border: 'none', fontSize: 12,
            boxShadow: '0 8px 24px rgb(0 0 0 / 0.12)',
            background: dark ? '#1f2937' : '#fff', color: dark ? '#f1f5f9' : '#111827',
          }}
          labelStyle={{ color: dark ? '#94a3b8' : '#6b7280', marginBottom: 4 }}
          formatter={(v: number) => [format(v), 'Ingresos']}
        />
        <Area
          type="monotone" dataKey="value" stroke="#7C3AED" strokeWidth={2.5}
          fill="url(#mrrFill)" dot={false} activeDot={{ r: 4, strokeWidth: 2, stroke: '#fff' }}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
