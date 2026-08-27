import { useCallback, useSyncExternalStore } from 'react';

type Theme = 'light' | 'dark';
const KEY = 'gympro-admin-theme';

function read(): Theme {
  if (typeof window === 'undefined') return 'light';
  const saved = window.localStorage.getItem(KEY);
  if (saved === 'light' || saved === 'dark') return saved;
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

let current: Theme = read();
const listeners = new Set<() => void>();

function apply(t: Theme) {
  if (typeof document !== 'undefined') {
    document.documentElement.classList.toggle('dark', t === 'dark');
  }
}
apply(current);

function setTheme(t: Theme) {
  current = t;
  if (typeof window !== 'undefined') window.localStorage.setItem(KEY, t);
  apply(t);
  listeners.forEach((l) => l());
}

function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function useTheme() {
  const theme = useSyncExternalStore(subscribe, () => current, () => 'light' as Theme);
  const toggle = useCallback(() => setTheme(current === 'dark' ? 'light' : 'dark'), []);
  return { theme, toggle };
}
