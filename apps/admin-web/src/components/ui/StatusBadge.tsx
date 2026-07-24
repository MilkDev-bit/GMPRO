type Tone = 'green' | 'red' | 'amber' | 'sky' | 'indigo' | 'gray';

const TONES: Record<Tone, string> = {
  green:  'bg-emerald-100 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-400',
  red:    'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-400',
  amber:  'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-400',
  sky:    'bg-sky-100 text-sky-700 dark:bg-sky-500/15 dark:text-sky-400',
  indigo: 'bg-indigo-100 text-indigo-700 dark:bg-indigo-500/15 dark:text-indigo-400',
  gray:   'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300',
};

/** Badge "soft" TailAdmin: fondo semitransparente + texto sólido del mismo tono. */
export function StatusBadge({ tone, children }: { tone: Tone; children: React.ReactNode }) {
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${TONES[tone]}`}>
      {children}
    </span>
  );
}

export type { Tone };
