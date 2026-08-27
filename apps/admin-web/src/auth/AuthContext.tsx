import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { API, STAFF_ROLES } from '../lib/config';
import { http, setAccessToken, type ApiEnvelope } from '../lib/api';

interface StaffUser {
  id: string;
  email: string;
  nombre?: string;
  rol: string;
}

interface AuthCtx {
  user: StaffUser | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const Ctx = createContext<AuthCtx | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<StaffUser | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const res = await fetch(`${API.auth}/refresh`, { method: 'POST', credentials: 'include' });
        if (res.ok) {
          const json = (await res.json()) as ApiEnvelope<{ accessToken: string }>;
          if (json.data?.accessToken) {
            setAccessToken(json.data.accessToken);
            const me = await http.get<StaffUser>(`${API.auth}/me`);
            if (me && STAFF_ROLES.includes(me.rol as (typeof STAFF_ROLES)[number])) setUser(me);
            else await doLogout();
          }
        }
      } catch { /* sin sesión */ } finally { setLoading(false); }
    })();
  }, []);

  async function login(email: string, password: string) {
    const data = await http.post<{ accessToken: string; user: StaffUser }>(
      `${API.auth}/login`, { email, password },
    );
    if (!STAFF_ROLES.includes(data.user.rol as (typeof STAFF_ROLES)[number])) {
      setAccessToken(null);
      throw new Error('Esta cuenta no tiene permisos de administración.');
    }
    setAccessToken(data.accessToken);
    setUser(data.user);
  }

  async function doLogout() {
    try { await http.post(`${API.auth}/logout`); } catch { /* best-effort */ }
    setAccessToken(null);
    setUser(null);
  }

  const value = useMemo<AuthCtx>(() => ({ user, loading, login, logout: doLogout }), [user, loading]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAuth() {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error('useAuth debe usarse dentro de <AuthProvider>');
  return ctx;
}
