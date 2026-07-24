import { Cell, Pie, PieChart, ResponsiveContainer } from 'recharts';

interface Props {
  /** Porcentaje 0..100. */
  value: number;
  dark?: boolean;
  centerLabel?: string;
  height?: number;
}

/**
 * Dona/gauge de retención: pista de fondo gris muy clara + progreso morado,
 * con el porcentaje centrado dentro de la dona.
 */
export function RetentionDonut({ value, dark, centerLabel = 'Retención', height = 240 }: Props) {
  const pct = Math.max(0, Math.min(100, value));
  const track = dark ? '#374151' : '#EDE9FE';
  const data = [
    { name: 'progreso', value: pct },
    { name: 'resto', value: 100 - pct },
  ];

  return (
    <div className="relative" style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Pie
            data={data}
            dataKey="value"
            innerRadius="72%"
            outerRadius="100%"
            startAngle={90}
            endAngle={-270}
            stroke="none"
            paddingAngle={0}
            cornerRadius={8}
          >
            <Cell fill="#7C3AED" />
            <Cell fill={track} />
          </Pie>
        </PieChart>
      </ResponsiveContainer>
      <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
        <span className="text-3xl font-bold text-gray-900 dark:text-white tabular-nums">
          {pct.toFixed(1)}%
        </span>
        <span className="text-xs text-gray-500 dark:text-gray-400 mt-1">{centerLabel}</span>
      </div>
    </div>
  );
}
