import type { ReactNode } from 'react';

interface CardProps {
  children: ReactNode;
  className?: string;
  /** Padding interno (por defecto p-6). Pásalo vacío para tablas full-bleed. */
  padding?: string;
}

/** Tarjeta base TailAdmin: blanca, borde sutil, sombra suave, radio pronunciado. */
export function Card({ children, className = '', padding = 'p-6' }: CardProps) {
  return (
    <div
      className={`bg-white dark:bg-gray-800 border border-gray-100 dark:border-gray-700 rounded-2xl shadow-card ${padding} ${className}`}
    >
      {children}
    </div>
  );
}

interface CardHeaderProps {
  title: string;
  subtitle?: string;
  action?: ReactNode;
}

/** Encabezado de card con título/subtítulo a la izquierda y acción a la derecha. */
export function CardHeader({ title, subtitle, action }: CardHeaderProps) {
  return (
    <div className="flex items-start justify-between gap-3 mb-5">
      <div>
        <h3 className="text-base font-semibold text-gray-900 dark:text-white">{title}</h3>
        {subtitle && <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}
