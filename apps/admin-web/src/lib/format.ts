export const money = (n: number, currency = 'MXN') =>
  new Intl.NumberFormat('es-MX', { style: 'currency', currency }).format(n ?? 0);

export const date = (iso?: string | null) =>
  iso ? new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium' }).format(new Date(iso)) : '—';
