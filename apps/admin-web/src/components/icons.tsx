// Iconos outline inline (estilo Heroicons/Lucide) — sin dependencia externa.
// Heredan el color vía `currentColor` y el tamaño vía `className` (w-5 h-5).

import type { SVGProps } from 'react';

type IconProps = SVGProps<SVGSVGElement>;

const base = (props: IconProps) => ({
  width: 20,
  height: 20,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.7,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  ...props,
});

export const DashboardIcon = (p: IconProps) => (
  <svg {...base(p)}><rect x="3" y="3" width="7" height="9" rx="1.5" /><rect x="14" y="3" width="7" height="5" rx="1.5" /><rect x="14" y="12" width="7" height="9" rx="1.5" /><rect x="3" y="16" width="7" height="5" rx="1.5" /></svg>
);

export const MembersIcon = (p: IconProps) => (
  <svg {...base(p)}><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M22 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" /></svg>
);

export const FinanceIcon = (p: IconProps) => (
  <svg {...base(p)}><path d="M3 3v18h18" /><path d="M7 15l3-4 3 2 5-6" /></svg>
);

export const OffersIcon = (p: IconProps) => (
  <svg {...base(p)}><path d="M20.59 13.41 13.42 20.6a2 2 0 0 1-2.83 0L3 13V3h10l7.59 7.59a2 2 0 0 1 0 2.82Z" /><circle cx="7.5" cy="7.5" r="1.5" /></svg>
);

export const SearchIcon = (p: IconProps) => (
  <svg {...base(p)}><circle cx="11" cy="11" r="7" /><path d="m21 21-4.3-4.3" /></svg>
);

export const BellIcon = (p: IconProps) => (
  <svg {...base(p)}><path d="M18 8a6 6 0 1 0-12 0c0 7-3 9-3 9h18s-3-2-3-9" /><path d="M13.73 21a2 2 0 0 1-3.46 0" /></svg>
);

export const SunIcon = (p: IconProps) => (
  <svg {...base(p)}><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" /></svg>
);

export const MoonIcon = (p: IconProps) => (
  <svg {...base(p)}><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79Z" /></svg>
);

export const LogoutIcon = (p: IconProps) => (
  <svg {...base(p)}><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" /><path d="m16 17 5-5-5-5" /><path d="M21 12H9" /></svg>
);

export const ArrowUpIcon = (p: IconProps) => (
  <svg {...base({ width: 14, height: 14, strokeWidth: 2.2, ...p })}><path d="M12 19V5" /><path d="m5 12 7-7 7 7" /></svg>
);

export const ArrowDownIcon = (p: IconProps) => (
  <svg {...base({ width: 14, height: 14, strokeWidth: 2.2, ...p })}><path d="M12 5v14" /><path d="m19 12-7 7-7-7" /></svg>
);

export const UsersGroupIcon = (p: IconProps) => (
  <svg {...base(p)}><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /></svg>
);

export const CreditCardIcon = (p: IconProps) => (
  <svg {...base(p)}><rect x="2" y="5" width="20" height="14" rx="2" /><path d="M2 10h20" /></svg>
);

export const AlertIcon = (p: IconProps) => (
  <svg {...base(p)}><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z" /><path d="M12 9v4M12 17h.01" /></svg>
);

export const TicketIcon = (p: IconProps) => (
  <svg {...base(p)}><path d="M4 8V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4Z" /></svg>
);
