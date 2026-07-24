// Contexto de autenticación del panel. Login contra auth-service; solo permite
// entrar a roles internos (staff/admin). El token se guarda en memoria (api.ts).

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

  // Al montar, intenta rehidratar sesión con la cookie de refresh.
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function login(email: string, password: string) {
    const data = await http.post<{ accessToken: string; user: StaffUser }>(
      `${API.auth}/login`, { email, password },
    );
    // Gate de rol: los socios NO entran al panel.
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
