import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

export interface AltasBajasPoint { label: string; altas: number; bajas: number; }

interface Props {
  data: AltasBajasPoint[];
  dark?: boolean;
  height?: number;
}

const AXIS = '#94a3b8';

export function AltasBajasBarChart({ data, dark, height = 300 }: Props) {
  const grid = dark ? '#334155' : '#eef2f7';
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 10, right: 8, left: 0, bottom: 0 }} barGap={6}>
        <CartesianGrid vertical={false} strokeDasharray="4 4" stroke={grid} />
        <XAxis dataKey="label" tickLine={false} axisLine={false} tick={{ fill: AXIS, fontSize: 12 }} dy={8} />
        <YAxis tickLine={false} axisLine={false} width={32} tick={{ fill: AXIS, fontSize: 12 }} allowDecimals={false} />
        <Tooltip
          cursor={{ fill: dark ? 'rgba(124,58,237,0.08)' : 'rgba(124,58,237,0.06)' }}
          contentStyle={{
            borderRadius: 12, border: 'none', fontSize: 12,
            boxShadow: '0 8px 24px rgb(0 0 0 / 0.12)',
            background: dark ? '#1f2937' : '#fff', color: dark ? '#f1f5f9' : '#111827',
          }}
        />
        <Legend
          iconType="circle" iconSize={9}
          wrapperStyle={{ fontSize: 12, paddingTop: 8, color: AXIS }}
        />
        <Bar dataKey="altas" name="Altas" fill="#7C3AED" radius={[4, 4, 0, 0]} maxBarSize={26} />
        <Bar dataKey="bajas" name="Bajas" fill={dark ? '#4c1d95' : '#DDD6FE'} radius={[4, 4, 0, 0]} maxBarSize={26} />
      </BarChart>
    </ResponsiveContainer>
  );
}
