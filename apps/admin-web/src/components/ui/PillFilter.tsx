interface PillFilterProps<T extends string> {
  options: readonly T[];
  value: T;
  onChange: (v: T) => void;
  /** Etiquetas legibles opcionales por opción. */
  labels?: Partial<Record<T, string>>;
}

/** Segmentador tipo pill (Mensual | Trimestral | Anual) estilo TailAdmin. */
export function PillFilter<T extends string>({ options, value, onChange, labels }: PillFilterProps<T>) {
  return (
    <div className="inline-flex items-center gap-1 p-1 rounded-lg bg-gray-100 dark:bg-gray-700/50">
      {options.map((opt) => {
        const active = opt === value;
        return (
          <button
            key={opt}
            onClick={() => onChange(opt)}
            className={`px-3 py-1 rounded-md text-xs font-medium capitalize transition-colors ${
              active
                ? 'bg-white dark:bg-gray-800 text-indigo-600 dark:text-indigo-400 shadow-sm'
                : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200'
            }`}
          >
            {labels?.[opt] ?? opt}
          </button>
        );
      })}
    </div>
  );
}
