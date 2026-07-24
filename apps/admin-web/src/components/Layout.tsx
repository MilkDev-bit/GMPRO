import { NavLink } from 'react-router-dom';
import type { ReactNode } from 'react';
import { useAuth } from '../auth/AuthContext';
import { useTheme } from '../lib/useTheme';
import { isAdmin } from '../lib/roles';
import {
  DashboardIcon, MembersIcon, FinanceIcon, OffersIcon,
  SearchIcon, BellIcon, SunIcon, MoonIcon, LogoutIcon,
} from './icons';

interface NavItem {
  to: string;
  label: string;
  icon: ReactNode;
  end?: boolean;
  adminOnly?: boolean;
}
interface NavGroup { group: string; items: NavItem[]; }

const NAV: NavGroup[] = [
  {
    group: 'Principal',
    items: [
      { to: '/', label: 'Dashboard', icon: <DashboardIcon />, end: true, adminOnly: true },
      { to: '/members', label: 'Miembros', icon: <MembersIcon /> },
    ],
  },
  {
    group: 'Finanzas',
    items: [
      { to: '/finance', label: 'Suscripciones', icon: <FinanceIcon />, adminOnly: true },
      { to: '/offers', label: 'Ofertas', icon: <OffersIcon />, adminOnly: true },
    ],
  },
];

function initials(name?: string, email?: string): string {
  const src = (name || email || '?').trim();
  const parts = src.split(/[\s@.]+/).filter(Boolean);
  return (parts[0]?.[0] ?? '?').toUpperCase() + (parts[1]?.[0]?.toUpperCase() ?? '');
}

export function Layout({ children }: { children: ReactNode }) {
  const { user, logout } = useAuth();
  const { theme, toggle } = useTheme();
  const admin = isAdmin(user ?? undefined);

  return (
    <div className="min-h-screen grid grid-cols-1 md:grid-cols-[260px_1fr] bg-gray-50 dark:bg-gray-900">
      {/* ── Sidebar ─────────────────────────────────────────────────────── */}
      <aside className="hidden md:flex flex-col bg-white dark:bg-gray-800 border-r border-gray-100 dark:border-gray-700">
        <div className="h-16 flex items-center gap-2 px-6 border-b border-gray-100 dark:border-gray-700">
          <span className="w-8 h-8 rounded-lg bg-brand text-white grid place-items-center font-bold text-sm">G</span>
          <span className="text-lg font-bold text-gray-900 dark:text-white">
            Gym<span className="text-brand">Pro</span>
          </span>
        </div>

        <nav className="flex-1 px-4 py-5 space-y-6 overflow-y-auto">
          {NAV.map((grp) => {
            const items = grp.items.filter((i) => admin || !i.adminOnly);
            if (items.length === 0) return null;
            return (
              <div key={grp.group}>
                <div className="px-3 mb-2 text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">
                  {grp.group}
                </div>
                <div className="space-y-1">
                  {items.map((n) => (
                    <NavLink
                      key={n.to}
                      to={n.to}
                      end={n.end}
                      className={({ isActive }) =>
                        `flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors ${
                          isActive
                            ? 'bg-indigo-50 text-indigo-600 dark:bg-indigo-500/10 dark:text-indigo-400'
                            : 'text-gray-500 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-700/50 hover:text-gray-700 dark:hover:text-gray-200'
                        }`
                      }
                    >
                      {n.icon}
                      {n.label}
                    </NavLink>
                  ))}
                </div>
              </div>
            );
          })}
        </nav>

        <div className="px-4 py-4 border-t border-gray-100 dark:border-gray-700">
          <div className="flex items-center gap-3 px-2">
            <span className="w-9 h-9 rounded-full bg-brand/10 text-brand grid place-items-center text-sm font-semibold">
              {initials(user?.nombre, user?.email)}
            </span>
            <div className="min-w-0 flex-1">
              <div className="text-sm font-medium text-gray-900 dark:text-white truncate">
                {user?.nombre ?? user?.email}
              </div>
              <div className="text-xs text-gray-400 dark:text-gray-500 capitalize">{user?.rol}</div>
            </div>
            <button
              onClick={() => void logout()}
              title="Cerrar sesión"
              className="text-gray-400 hover:text-red-500 transition-colors"
            >
              <LogoutIcon />
            </button>
          </div>
        </div>
      </aside>

      {/* ── Contenido ───────────────────────────────────────────────────── */}
      <div className="flex flex-col min-w-0">
        {/* Topbar */}
        <header className="h-16 flex items-center justify-between gap-4 px-4 md:px-8 bg-white dark:bg-gray-800 border-b border-gray-100 dark:border-gray-700 sticky top-0 z-10">
          <div className="relative w-full max-w-md">
            <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
            <input
              type="text"
              placeholder="Buscar o escribir comando…"
              className="w-full pl-10 pr-16 py-2 rounded-lg text-sm bg-gray-50 dark:bg-gray-700/50 border border-gray-100 dark:border-gray-700 text-gray-700 dark:text-gray-200 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-200 dark:focus:ring-indigo-500/30"
            />
            <kbd className="hidden sm:flex absolute right-3 top-1/2 -translate-y-1/2 items-center gap-0.5 text-[11px] text-gray-400 border border-gray-200 dark:border-gray-600 rounded px-1.5 py-0.5">
              ⌘K
            </kbd>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={toggle}
              title="Cambiar tema"
              className="w-10 h-10 grid place-items-center rounded-full text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
            >
              {theme === 'dark' ? <SunIcon /> : <MoonIcon />}
            </button>
            <button
              title="Notificaciones"
              className="relative w-10 h-10 grid place-items-center rounded-full text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
            >
              <BellIcon />
              <span className="absolute top-2.5 right-2.5 w-2 h-2 rounded-full bg-red-500 ring-2 ring-white dark:ring-gray-800" />
            </button>
            <span className="w-9 h-9 rounded-full bg-brand/10 text-brand grid place-items-center text-sm font-semibold">
              {initials(user?.nombre, user?.email)}
            </span>
          </div>
        </header>

        <main className="flex-1 p-4 md:p-8 overflow-auto">{children}</main>
      </div>
    </div>
  );
}
